const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {chromium} = require("playwright");

const siteRoot = path.resolve(__dirname,"..");
const mime = {".html":"text/html; charset=utf-8",".js":"application/javascript",".docx":"application/vnd.openxmlformats-officedocument.wordprocessingml.document"};
const persistenceMigration = fs.readFileSync(
  path.join(siteRoot,"supabase/migrations/20260930003000_student_user_tests.sql"),
  "utf8"
);
assert.match(persistenceMigration,/create table if not exists public\.medquiz_user_tests/i);
assert.match(persistenceMigration,/file_size_limit,\s*allowed_mime_types[\s\S]*20971520/i);
assert.match(persistenceMigration,/bucket_id = 'medquiz-user-tests'/i);
assert.match(persistenceMigration,/storage\.foldername\(name\).*auth\.uid/i);

const server = http.createServer((request,response)=>{
  const requestPath = request.url.split("?")[0] === "/" ? "/index.html" : request.url.split("?")[0];
  const filePath = path.join(siteRoot,requestPath);
  if(!filePath.startsWith(siteRoot) || !fs.existsSync(filePath)){
    response.writeHead(404);
    response.end("Not found");
    return;
  }
  response.writeHead(200,{"content-type":mime[path.extname(filePath)] || "application/octet-stream"});
  fs.createReadStream(filePath).pipe(response);
});

const browserMocks = `
window.pdfjsLib = {GlobalWorkerOptions:{}};
window.__insertedRows = [];
window.__uploadedPaths = [];
function query(table){
  const result = {data:[],error:null,count:0};
  const builder = {
    select(){return builder},eq(){return builder},neq(){return builder},not(){return builder},is(){return builder},
    in(){return builder},gt(){return builder},lt(){return builder},order(){return builder},limit(){return builder},
    update(){return builder},insert(payload){window.__insertedRows.push({table,payload});return builder},upsert(){return builder},delete(){return builder},
    maybeSingle(){return Promise.resolve({data:null,error:null})},single(){return Promise.resolve({data:null,error:null})},
    then(resolve,reject){return Promise.resolve(result).then(resolve,reject)}
  };
  return builder;
}
window.__mockClient = {
  auth:{
    getSession:()=>Promise.resolve({data:{session:null}}),
    onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})
  },
  from:table=>query(table),
  rpc:()=>Promise.resolve({data:[],error:null}),
  storage:{from:bucket=>({
    download:()=>Promise.resolve({data:null,error:{message:"not found"}}),
    upload:(path)=>{window.__uploadedPaths.push({bucket,path});return Promise.resolve({data:{path},error:null})},
    remove:()=>Promise.resolve({data:[],error:null})
  })}
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
  await page.addInitScript(browserMocks);
  await page.goto(`http://127.0.0.1:${port}/index.html`,{waitUntil:"domcontentloaded"});

  if(process.env.CHECK_DOCX_PATH){
    await page.evaluate(()=>{
      document.getElementById("quizSetupPanel").classList.remove("hidden");
      document.getElementById("importControls").classList.remove("hidden");
    });
    await page.locator("#file").setInputFiles(process.env.CHECK_DOCX_PATH);
    await page.waitForFunction(()=>!["selected","checking"].includes(studentImportValidation.status));
    const result = await page.evaluate(()=>({
      validation:studentImportValidation,
      statusText:document.getElementById("status").innerText,
      panelText:document.getElementById("importValidation").innerText,
      acceptedQuestions:cachedQuestions.map(question=>({
        num:question.num,
        question:question.q,
        correct:question.correct,
        optionCount:question.opts.length,
        explanation:question.explanation || "",
        explanationSource:question.explanationSource || ""
      }))
    }));
    console.log(JSON.stringify(result,null,2));
    await browser.close();
    server.close();
    return;
  }

  const parsed = await page.evaluate(()=>{
    const paragraph = (text,bold=true,index=1,runs=null)=>({
      text,
      rawText:text,
      paragraphIndex:index,
      runs:runs || [{text,bold}]
    });
    const rows = [];
    let index = 0;
    const add = (text,bold=false,runs=null)=>rows.push(paragraph(text,bold,++index,runs));

    add("1. Один полностью жирный вариант");
    add("A) Нет"); add("B) Да",true); add("C) Нет");
    add("2. Нет жирного варианта");
    add("A) Один"); add("B) Два");
    add("3. Несколько жирных вариантов");
    add("A) Один",true); add("B) Два",true);
    add("4. Частично жирный вариант");
    add("A) Частичный ответ",false,[{text:"A) Частичный",bold:true},{text:" ответ",bold:false}]);
    add("B) Обычный ответ");
    add("5. Жирный текст внутри вопроса",true);
    add("A) Неверно"); add("B) Верно",true);
    add("6. Есть объяснение");
    add("A) Верно",true); add("B) Неверно");
    add("Объяснение: Краткое объяснение.");
    add("7. Нет объяснения");
    add("A) Верно",true); add("B) Неверно");
    add("8. Объяснение из нескольких абзацев");
    add("A) Верно",true); add("B) Неверно");
    add("Объяснение: Первый абзац."); add("Второй абзац.");
    add("9. Есть источник и следующий вопрос начинается сразу");
    add("A) Верно",true); add("B) Неверно");
    add("Объяснение: Текст перед источником.");
    add("Источник: Учебник, глава 5.");
    add("10. Следующий вопрос");
    add("A) Верно",true); add("B) Неверно");
    add("Раздел 8 Дополнительный раздел");
    add("11. Кириллические варианты с точкой");
    add("А. Неверно"); add("Б. Верно",true); add("В. Неверно");
    add("Обоснование. Основное объяснение.");
    add("Разбор дистракторов. Дополнительный разбор.");
    add("Краткий ключ");
    add("1. Эта строка относится к источникам, а не к вопросам");

    return buildStudentDocxQuestions(rows);
  });

  assert.deepEqual(parsed.acceptedQuestions.map(question=>question.num),[1,5,6,7,8,9,10,11]);
  assert.match(parsed.problems.find(problem=>problem.num === 2).reasons.join(" "),/нет полностью жирного/);
  assert.match(parsed.problems.find(problem=>problem.num === 3).reasons.join(" "),/несколько вариантов/);
  assert.match(parsed.problems.find(problem=>problem.num === 4).reasons.join(" "),/только часть варианта/);
  assert.equal(parsed.problems.some(problem=>problem.num === 5),false);
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 6).explanation,"Краткое объяснение.");
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 7).explanation,"");
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 8).explanation,"Первый абзац.\n\nВторой абзац.");
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 9).explanationSource,"Учебник, глава 5.");
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 10).q,"Следующий вопрос");
  assert.deepEqual(parsed.acceptedQuestions.find(question=>question.num === 11).letters,["A","B","C"]);
  assert.equal(parsed.acceptedQuestions.find(question=>question.num === 11).correct,1);
  assert.equal(
    parsed.acceptedQuestions.find(question=>question.num === 11).explanation,
    "Основное объяснение.\n\nРазбор дистракторов. Дополнительный разбор."
  );
  assert.equal(parsed.rawQuestions.length,11);

  await page.evaluate(()=>{
    document.getElementById("quizSetupPanel").classList.remove("hidden");
    document.getElementById("importControls").classList.remove("hidden");
  });
  await page.locator("#file").setInputFiles(path.join(siteRoot,"student-test-example.docx"));
  await page.locator("#importValidation.valid").waitFor();
  assert.match(await page.locator("#importValidation").innerText(),/Распознано вопросов: 2/);
  assert.equal(await page.evaluate(()=>studentImportValidation.status),"recognized");
  assert.equal(await page.locator("#startBtn").isEnabled(),true);

  const fileValidation = await page.evaluate(async()=>{
    const check = async(file)=>{
      try{
        return await validateStudentImportFile(file);
      }catch(error){
        return error.message;
      }
    };
    return {
      pdf:await check(new File(["%PDF-1.7"],"valid.pdf",{type:"application/pdf"})),
      fakePdf:await check(new File(["not a pdf"],"fake.pdf",{type:"application/pdf"})),
      wrongMime:await check(new File(["%PDF-1.7"],"wrong.pdf",{type:"text/plain"})),
      wrongExtension:await check(new File(["%PDF-1.7"],"wrong.txt",{type:"application/pdf"}))
    };
  });
  assert.equal(fileValidation.pdf,"pdf");
  assert.match(fileValidation.fakePdf,/не является PDF/);
  assert.match(fileValidation.wrongMime,/не соответствует расширению/);
  assert.match(fileValidation.wrongExtension,/расширением PDF или DOCX/);

  const persisted = await page.evaluate(async()=>{
    currentUser = {id:"11111111-1111-4111-8111-111111111111"};
    currentTestName = "Проверочный тест";
    studentImportValidation = {status:"recognized",questionCount:1,problems:[]};
    const file = new File(["%PDF-1.7"],"saved.pdf",{type:"application/pdf"});
    const questions = [{num:1,q:"Вопрос",opts:["Да","Нет"],correct:0}];
    const saved = await persistStudentImportedTest(file,questions);
    return {
      saved,
      status:studentImportValidation.status,
      uploads:window.__uploadedPaths,
      inserted:window.__insertedRows.find(item=>item.table === "medquiz_user_tests")
    };
  });
  assert.equal(persisted.status,"saved");
  assert.deepEqual(persisted.uploads.map(item=>item.bucket),["medquiz-user-tests","medquiz-user-tests"]);
  assert.match(persisted.uploads[0].path,/\/source\.pdf$/);
  assert.match(persisted.uploads[1].path,/\/questions\.json$/);
  assert.equal(persisted.inserted.payload.owner_user_id,"11111111-1111-4111-8111-111111111111");
  assert.equal(persisted.inserted.payload.question_count,1);

  await page.evaluate(()=>handleImportFile({
    name:"too-large.docx",
    type:"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    size:STUDENT_IMPORT_MAX_BYTES + 1
  }));
  assert.match(await page.locator("#status").innerText(),/Максимальный размер — 20 МБ/);

  await page.evaluate(()=>{
    selectedImportFile = {
      name:"invalid.docx",
      type:"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      size:1024
    };
    studentImportValidation = {
      status:"invalid",
      questionCount:1,
      problems:[{num:1,reasons:["нет полностью жирного варианта ответа"]}]
    };
    renderStudentImportValidation();
    refreshStartButtonState();
  });
  assert.equal(await page.locator("#startBtn").isDisabled(),true);
  assert.match(await page.locator("#importValidation").innerText(),/Вопрос 1.*нет полностью жирного/s);

  const displayChecks = await page.evaluate(()=>{
    const sample = {
      num:1,
      q:"Вопрос",
      opts:["Верно","Неверно"],
      letters:["A","B"],
      correct:0,
      explanation:"Первый абзац.\n\nВторой абзац.",
      explanationSource:"Учебник"
    };
    test = [sample];
    current = 0;
    userAnswers = [0];
    mode = "exam";
    showQ();
    const examResult = document.getElementById("result").innerText;
    const examCorrectVisible = Boolean(document.querySelector("#quiz .answer-option.correct"));
    mode = "training";
    showQ();
    const trainingResult = document.getElementById("result").innerText;
    const noExplanationHtml = questionExplanationHtml({...sample,explanation:"",explanationSource:""});
    return {examResult,examCorrectVisible,trainingResult,noExplanationHtml};
  });
  assert.equal(displayChecks.examResult,"");
  assert.equal(displayChecks.examCorrectVisible,false);
  assert.match(displayChecks.trainingResult,/Первый абзац/);
  assert.match(displayChecks.trainingResult,/Источник: Учебник/);
  assert.equal(displayChecks.noExplanationHtml,"");

  await browser.close();
  server.close();
  console.log("student DOCX import browser: all checks passed");
})().catch(error=>{
  server.close();
  console.error(error);
  process.exitCode = 1;
});
