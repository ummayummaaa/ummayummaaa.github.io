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
  const browser = await chromium.launch({headless:true,executablePath:"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  try{
    for(const width of [320,390,1100]){
      const page = await browser.newPage({viewport:{width,height:800}});
      await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:""}));
      await page.addInitScript(mockServices);
      await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:"domcontentloaded"});
      await page.waitForSelector(".subject-row");
      await page.evaluate(()=>{
        requireWritableAccount=()=>true;
        persistCurrentAnswer=async()=>{};
        test=[{num:1,q:"Проверка длинного вопроса ".repeat(25),opts:["Неверный ответ","Правильный ответ"],correct:1},{num:2,q:"Второй вопрос",opts:["А","Б"],correct:0}];
        userAnswers=[null,null];current=0;mode="training";
        document.querySelector(".app").classList.add("testing");showQ();
      });
      assert.equal(await page.locator("#previousQuestion").isDisabled(),true);
      assert.equal(await page.locator("#forwardQuestion").isDisabled(),true);
      await page.locator(".answer-option").first().click();
      const colors=await page.evaluate(()=>{
        const wrong=getComputedStyle(document.querySelector(".answer-option.wrong"));
        const number=getComputedStyle(document.querySelector(".question-number.wrong"));
        const correct=getComputedStyle(document.querySelector(".answer-option.correct"));
        return {wrong:wrong.backgroundColor,number:number.backgroundColor,border:wrong.borderColor,numberBorder:number.borderColor,correct:correct.backgroundColor};
      });
      assert.equal(colors.wrong,colors.number);assert.equal(colors.border,colors.numberBorder);assert.notEqual(colors.wrong,colors.correct);
      assert.equal(await page.locator("#forwardQuestion").isDisabled(),false);
      await page.evaluate(()=>window.scrollTo(0,document.body.scrollHeight));
      const arrow=await page.locator("#forwardQuestion").boundingBox();
      assert.ok(arrow.x>=0 && arrow.x+arrow.width<=width && arrow.y>=0 && arrow.y+arrow.height<=800);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
      await page.screenshot({path:`/tmp/medquiz-navigation-${width}.png`});
      await page.locator("#forwardQuestion").click();
      assert.equal(await page.evaluate(()=>current),1);
      assert.equal(await page.locator("#forwardQuestion").getAttribute("aria-label"),"Завершить тест");
      await page.locator("#previousQuestion").click();
      assert.equal(await page.evaluate(()=>current),0);
      assert.equal(await page.locator(".answer-option.wrong").count(),1);
      await page.evaluate(()=>{document.querySelector(".app").classList.remove("testing")});
      assert.equal(await page.locator("#forwardQuestion").isVisible(),false);
      await page.close();
    }
    console.log("Quiz feedback and navigation passed at 320, 390, 1100px");
  }finally{
    await browser.close();
    server.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1});
