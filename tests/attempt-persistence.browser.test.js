const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {chromium} = require("playwright");

const siteRoot = path.resolve(__dirname,"..");
const mime = {".html":"text/html; charset=utf-8",".js":"application/javascript"};
const server = http.createServer((request,response)=>{
  const requestPath = request.url.split("?")[0] === "/" ? "/index.html" : request.url.split("?")[0];
  const filePath = path.join(siteRoot,requestPath);
  if(!filePath.startsWith(siteRoot) || !fs.existsSync(filePath)){
    response.writeHead(404).end("Not found");
    return;
  }
  response.writeHead(200,{"content-type":mime[path.extname(filePath)] || "application/octet-stream"});
  fs.createReadStream(filePath).pipe(response);
});

const mockSupabase = `
window.pdfjsLib = {GlobalWorkerOptions:{}};
window.__blockScenario = "success";
window.__blockQueryCount = 0;
window.__blockRpcCount = 0;
const blockStates = [
  {block_start:1,has_checks:true,ever_passed:false,last_percent:70,best_percent:70},
  {block_start:51,has_checks:true,ever_passed:true,last_percent:95,best_percent:95},
  {block_start:101,has_checks:true,ever_passed:true,last_percent:80,best_percent:96}
];
function blockResult(){
  if(window.__blockScenario === "hang") return new Promise(()=>{});
  if(window.__blockScenario === "error") return Promise.resolve({data:null,error:{message:"missing table"}});
  return new Promise(resolve=>setTimeout(()=>resolve({data:blockStates,error:null}),180));
}
function genericResult(table){
  if(table === "medquiz_profiles") return {data:{is_admin:false,account_status:"active",access_type:"lifetime",access_expires_at:null},error:null};
  return {data:[],error:null,count:0};
}
function query(table){
  const builder = {
    select(){ return builder; },eq(){ return builder; },order(){ return builder; },limit(){ return builder; },
    maybeSingle(){ return Promise.resolve(genericResult(table)); },single(){ return Promise.resolve(genericResult(table)); },
    then(resolve,reject){
      if(table === "medquiz_block_states"){
        window.__blockQueryCount++;
        return blockResult().then(resolve,reject);
      }
      return Promise.resolve(genericResult(table)).then(resolve,reject);
    }
  };
  return builder;
}
window.__mockClient = {
  auth:{
    getSession:()=>Promise.resolve({data:{session:null}}),
    onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})
  },
  from:query,
  rpc(name){
    if(name === "medquiz_admin_get_block_states"){
      window.__blockRpcCount++;
      return blockResult();
    }
    return Promise.resolve({data:[],error:null});
  }
};
window.supabase = {createClient:()=>window.__mockClient};
`;

(async()=>{
  await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
  const port = server.address().port;
  const browser = await chromium.launch({headless:true,executablePath:"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:"window.supabase={createClient:()=>window.__mockClient};"}));
  await page.route("https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",route=>route.fulfill({contentType:"application/javascript",body:"window.pdfjsLib={GlobalWorkerOptions:{}};"}));
  await page.addInitScript(mockSupabase);
  await page.goto(`http://127.0.0.1:${port}/index.html`,{waitUntil:"domcontentloaded"});

  // Guest: cards render immediately, including an incomplete final block, without a stats request.
  await page.evaluate(()=>openBlocks("stomatologia"));
  assert.equal(await page.locator(".block-card").count(),15);
  assert.match(await page.locator(".block-card").last().innerText(),/701–739 · 39 вопросов/);
  assert.equal(await page.evaluate(()=>window.__blockQueryCount),0);
  assert.equal(await page.getByRole("button",{name:"Тренировка"}).count(),15);
  assert.equal(await page.getByRole("button",{name:"Проверка блока"}).count(),15);


 const result=await page.evaluate(async()=>{
  const writes=[];
  function query(table){const b={select(){return b},eq(){return b},in(){return b},single:async()=>({data:{id:'original'},error:null}),insert(rows){writes.push({table,rows:JSON.parse(JSON.stringify(rows))});return b},update(rows){writes.push({table,rows:JSON.parse(JSON.stringify(rows))});return b},upsert(rows){writes.push({table,rows:JSON.parse(JSON.stringify(rows))});return b},then(a,z){return Promise.resolve({data:[],error:null}).then(a,z)}};return b}
  supabaseClient.from=query;currentUser={id:'test'};currentUserHasFullAccess=true;loadDashboardStats=async()=>{};
  function original(){currentTestId='library-stomatologia';currentTestName='Original';mode='training';currentAttemptKind='training';testStartedAt=Date.now();test=[{num:51,q:'Original question',opts:['a','b'],correct:0}];questions=[...test];userAnswers=[0];score=1;favoriteKeys=new Set([questionKey(test[0])]);}
  function next(){test[0].opts[0]='changed';test=[{num:99,q:'Next question',opts:['c','d'],correct:1}];questions=[...test];userAnswers=[0];score=0;favoriteKeys.clear();currentAttemptKind='general_exam';}
  const resolver=resolveAttemptScope;
  original();let release;resolveAttemptScope=()=>new Promise(r=>release=r);
  const saving=saveCompletedAttempt({activeAttemptPromise:Promise.resolve('original')});next();release({spaceId:'dentistry',subjectId:'stomatologia'});await saving;
  const completion=writes.splice(0);
  original();const starting=startActiveAttempt();next();release({spaceId:'dentistry',subjectId:'stomatologia'});await starting;const startup=writes.splice(0);
  original();currentAttemptPromise=new Promise(r=>release=r);const answer=persistCurrentAnswer(0,0);next();release('original');await answer;const answerWrites=writes.splice(0);
  original();resolveAttemptScope=async()=>{await Promise.resolve();throw {message:'column space_id does not exist',code:'42703'}};
  const fallback=saveCompletedAttempt();next();await fallback;const legacy=writes.splice(0);resolveAttemptScope=resolver;
  return {completion,startup,answerWrites,legacy};
 });
 for(const records of [result.completion,result.startup,result.legacy]){
 const saved=records.find(x=>x.table==='medquiz_attempts').rows;assert.equal(saved.correct_answers,records===result.startup?0:1);assert.equal(saved.test_name,'Original');
 const answers=records.find(x=>x.table===(records===result.startup?'medquiz_attempt_questions':'medquiz_answers')).rows;
 assert.equal(answers[0].question_key,'51_Original question');assert.equal(answers[0].is_correct,true);
 }
 assert.equal(result.completion.find(x=>x.table==='medquiz_attempt_questions').rows[0].options[0],'a');
 assert.equal(result.completion.find(x=>x.table==='medquiz_question_stats').rows[0].favorite,true);
 assert.equal(result.answerWrites.find(x=>x.table==='medquiz_attempt_questions').rows.is_correct,true);
 await browser.close();server.close();console.log('Attempt persistence: completion, startup, pending answer and legacy fallback passed');
})().catch(e=>{console.error(e);process.exit(1)});
