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
    for(const width of [320,390]){
      const page = await browser.newPage({viewport:{width,height:800}});
      await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:""}));
      await page.route("https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",route=>route.fulfill({contentType:"application/javascript",body:"window.pdfjsLib={GlobalWorkerOptions:{},getDocument:()=>({})};"}));
      await page.addInitScript(mockServices);
      await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:"domcontentloaded"});
      await page.waitForSelector(".subject-row");

      assert.equal(await page.locator(".sidebar").evaluate(element=>getComputedStyle(element).display),"none");
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
      assert.equal(await page.locator('script[src*="pdf.min.js"],script[src*="jszip-3.10.1.min.js"]').count(),0);
      await page.locator(".mobile-nav > button").nth(1).click();
      assert.match(await page.locator("#sectionView h2").innerText(),/Предметы/);
      await page.locator(".section-item .secondary").first().click();
      await page.waitForSelector(".subject-banner h2");
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);

      await page.locator("#mobileMore summary").click();
      assert.equal(await page.locator(".mobile-more-panel").isVisible(),true);
      await page.locator(".mobile-more-panel button").first().click();
      assert.match(await page.locator("#sectionView h2").innerText(),/Избранное/);
      assert.equal(await page.locator("#mobileMore").getAttribute("open"),null);
      await page.locator("#mobileMore summary").click();
      await page.locator(".mobile-more-panel button").nth(1).click();
      assert.match(await page.locator("#sectionView h2").innerText(),/История/);
      await page.locator("#mobileMore summary").click();
      await page.keyboard.press("Escape");
      assert.equal(await page.locator("#mobileMore").getAttribute("open"),null);
      await page.locator("#mobileMore summary").click();
      await page.locator(".mobile-more-panel button").last().click();
      assert.equal(await page.locator("#authModal").isVisible(),true);
      const dialog = await page.locator("#authModal .auth-card").boundingBox();
      assert.ok(dialog.x >= 0 && dialog.x + dialog.width <= width);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth),width);
      if(width === 320){
        await page.evaluate(()=>Promise.all([ensurePdfJs(),ensureJSZip()]));
        assert.equal(await page.locator('script[src*="pdf.min.js"],script[src*="jszip-3.10.1.min.js"]').count(),2);
      }
      await page.close();
    }
    const desktop = await browser.newPage({viewport:{width:1100,height:800}});
    await desktop.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:""}));
    await desktop.route("https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",route=>route.fulfill({contentType:"application/javascript",body:""}));
    await desktop.addInitScript(mockServices);
    await desktop.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:"domcontentloaded"});
    assert.equal(await desktop.locator(".sidebar").isVisible(),true);
    await desktop.close();
    console.log("Mobile layout and navigation passed at 320px and 390px; desktop sidebar passed");
  }finally{
    await browser.close();
    server.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1});
