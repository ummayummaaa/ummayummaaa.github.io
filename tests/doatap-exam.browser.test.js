const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {chromium} = require("playwright");

const root = path.resolve(__dirname,"..");
const server = http.createServer((request,response)=>{
  const pathname = decodeURIComponent(request.url.split("?")[0]);
  const file = path.join(root,pathname === "/" ? "index.html" : pathname);
  if(!file.startsWith(root + path.sep) || !fs.existsSync(file)){
    response.writeHead(404);
    response.end();
    return;
  }
  response.setHeader("Content-Type",file.endsWith(".js") ? "application/javascript" : "text/html; charset=utf-8");
  fs.createReadStream(file).pipe(response);
});

const mockServices = `
window.pdfjsLib={GlobalWorkerOptions:{}};
function query(){
  const result={data:[],error:null,count:0};
  const builder={
    select(){return builder},eq(){return builder},neq(){return builder},not(){return builder},
    is(){return builder},in(){return builder},gt(){return builder},lt(){return builder},
    order(){return builder},limit(){return builder},
    maybeSingle(){return Promise.resolve({data:null,error:null})},
    single(){return Promise.resolve({data:null,error:null})},
    then(resolve,reject){return Promise.resolve(result).then(resolve,reject)}
  };
  return builder;
}
window.supabase={createClient:()=>({
  auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},
  from:()=>query(),rpc:async()=>({data:[],error:null})
})};
`;

(async()=>{
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const browser=await chromium.launch({headless:true,executablePath:"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
 try{
  const page=await browser.newPage({viewport:{width:390,height:850}});
  const pageErrors=[];page.on('pageerror',e=>pageErrors.push(e.message));
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',r=>r.fulfill({contentType:'application/javascript',body:''}));
  await page.route('https://cdnjs.cloudflare.com/ajax/libs/pdf.js/**',r=>r.fulfill({contentType:'application/javascript',body:'window.pdfjsLib={GlobalWorkerOptions:{}};'}));
  await page.addInitScript(mockServices);
  await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:'domcontentloaded'});
  await page.waitForSelector('.doatap-group');
  assert.equal(await page.locator('.doatap-group').count(),3);
  assert.equal(await page.locator('.doatap-group').nth(0).locator('.doatap-subjects button').count(),2);
  assert.equal(await page.locator('.doatap-group').nth(1).locator('.doatap-subjects button').count(),3);
  await page.evaluate(()=>{
   requireWritableAccount=()=>true;
   currentUser={id:'11111111-1111-4111-8111-111111111111'};currentUserHasFullAccess=true;
   loadDashboardStats=async()=>{};loadFavoritesForCurrentTest=async()=>{};
   window.examDB={};window.examWrites=[];
   supabaseClient.from=table=>{
    let op='read',payload,filters=[];
    const query={select(){return query},order(){return query},limit(){return query},
     eq(k,v){filters.push([k,v]);return query},in(){return query},neq(){return query},not(){return query},
     insert(v){op='insert';payload=v;return query},update(v){op='update';payload=v;return query},upsert(v){op='upsert';payload=v;return query},
     single(){return run(true)},maybeSingle(){return run(true)},then(a,b){return run(false).then(a,b)}};
    function run(single){
     const db=window.examDB;
     if(op==='insert'||op==='upsert'){
      const rows=(Array.isArray(payload)?payload:[payload]).map(x=>({...x}));
      if(table==='medquiz_attempts')rows.forEach(x=>x.id=x.id||'attempt-'+Object.keys(db).length+'-'+Date.now());
      if(op==='upsert'&&table==='medquiz_attempt_questions') db[table]=(db[table]||[]).filter(x=>!rows.some(y=>y.attempt_id===x.attempt_id&&y.position===x.position));
      db[table]=(db[table]||[]).concat(rows);window.examWrites.push({table,op,rows});
      return Promise.resolve({data:single?rows[0]:rows,error:null});
     }
     const rows=(db[table]||[]).filter(row=>filters.every(([k,v])=>row[k]===v));
     if(op==='update'){rows.forEach(row=>Object.assign(row,payload));window.examWrites.push({table,op,payload});}
     return Promise.resolve({data:single?rows[0]||null:rows,error:null});
    }
    return query;
   };
  });
  for(const [i,count] of [[0,100],[1,150],[2,150]]){
   await page.evaluate(async index=>{await openDoatapExam(window.MEDQUIZ_DOATAP.GROUPS[index].id);await currentAttemptPromise;},i);
   const sample=await page.evaluate(()=>({count:test.length,seconds:testTimeLimit,scoped:activeSpaceId,answers:test.map(q=>q.opts.at(-1)),subjects:[...new Set(test.map(q=>q.subjectId))]}));
   assert.equal(sample.count,count);assert.equal(sample.seconds,count*90);assert.equal(sample.scoped,'dentistry');
   assert.ok(sample.answers.every(a=>a==='Я не знаю ответ'));assert.equal(sample.subjects.length,i===0?2:3);
  }
  await page.locator('.doatap-unknown').click();
  assert.equal(await page.locator('.answer-feedback').count(),0,'exam must hide correctness');
  await page.locator('#forwardQuestion').click();await page.locator('#previousQuestion').click();
  assert.equal(await page.locator('.doatap-unknown.selected').count(),1);
  const restored=await page.evaluate(async()=>{
   const id=await currentAttemptPromise;
   const first=test[0];const key=questionKey(first);
   await persistCurrentAnswer(0,first.opts.length-1);
   test=[];userAnswers=[];currentTestId='';
   await resumeAttempt(id);
   return {count:test.length,time:testTimeLimit,answer:userAnswers[0],last:test[0].opts.length-1,kind:isDoatapExam(),key:questionKey(test[0]),beforeKey:key,id};
  });
  assert.equal(restored.count,150);assert.equal(restored.time,13500);assert.equal(restored.answer,restored.last);assert.equal(restored.kind,true);assert.equal(restored.key,restored.beforeKey);
  await page.evaluate(async()=>{await openDoatapExam(window.MEDQUIZ_DOATAP.GROUPS[0].id);await currentAttemptPromise;});
  for(const width of [320,390,1100]){
   await page.setViewportSize({width,height:850});
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
  }
  await page.evaluate(()=>{
   userAnswers=test.map((q,i)=>i<51?q.correct:i<56?(q.correct+1)%(q.opts.length-1):q.opts.length-1);
   finishTest();
  });
  await page.waitForFunction(()=>examDB.medquiz_attempts.some(a=>a.status==='completed'));
  assert.match(await page.locator('.doatap-result-details').innerText(),/Баллы: 50 из 100/);
  assert.match(await page.locator('.doatap-result-details').innerText(),/Ошибок: 5 · Не знаю: 44/);
  assert.match(await page.locator('.doatap-result-details').innerText(),/Порог 50% достигнут/);
  const saved=await page.evaluate(()=>examDB.medquiz_attempts.find(a=>a.status==='completed'));
  assert.equal(saved.correct_answers,51,'database correct count must remain an integer count');
  assert.equal(saved.space_id,'dentistry');assert.equal(saved.subject_id,null);
  await page.getByRole('button',{name:'Разобрать ответы',exact:true}).click();
  assert.match(await page.locator('.doatap-result-details').innerText(),/Баллы: 50 из 100/);
  await page.evaluate(async id=>{await openAttempt(id);},saved.id);
  assert.match(await page.locator('.doatap-result-details').innerText(),/Баллы: 50 из 100/);
  assert.equal(await page.locator('.review-answer').filter({hasText:'Я не знаю ответ'}).count(),1);
  await page.screenshot({path:'/tmp/medquiz-doatap-review.png',fullPage:true});
  await page.evaluate(()=>renderSpaceDashboard());
  await page.setViewportSize({width:390,height:850});
  await page.screenshot({path:'/tmp/medquiz-doatap-groups-390.png',fullPage:true});
  for(const width of [320,390,1100]){
   await page.setViewportSize({width,height:850});
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
  }
  await page.evaluate(()=>selectLearningSpace('medicine'));
  assert.equal(await page.locator('.doatap-group').count(),0);
  assert.match(await page.locator('.empty-learning').innerText(),/ещё не добавлены/);
  assert.deepEqual(pageErrors,[]);
  console.log('DOATAP browser: 3 real-bank exams, mobile layout, non-answer selection, saved/resumed attempts, exact score, persisted review and unchanged medicine passed');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
