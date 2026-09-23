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
    response.writeHead(404);
    response.end("Not found");
    return;
  }
  response.writeHead(200,{"content-type":mime[path.extname(filePath)] || "application/octet-stream"});
  fs.createReadStream(filePath).pipe(response);
});

const mockSupabase = `
window.pdfjsLib = {GlobalWorkerOptions:{}};
function query(){
  const result = {data:[],error:null,count:0};
  const builder = {
    select(){return builder},eq(){return builder},neq(){return builder},not(){return builder},is(){return builder},
    in(){return builder},gt(){return builder},lt(){return builder},order(){return builder},limit(){return builder},
    update(){return builder},insert(){return builder},upsert(){return builder},delete(){return builder},
    maybeSingle(){return Promise.resolve({data:null,error:null})},single(){return Promise.resolve({data:null,error:null})},
    then(resolve,reject){return Promise.resolve(result).then(resolve,reject)}
  };
  return builder;
}
window.__mockClient = {
  signupPayload:null,
  resetEmail:null,
  resendEmail:null,
  auth:{
    getSession:()=>Promise.resolve({data:{session:null}}),
    onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),
    signUp:payload=>{window.__mockClient.signupPayload=payload;return Promise.resolve({data:{session:null},error:null})},
    signInWithPassword:()=>Promise.resolve({error:null}),
    signInWithOAuth:()=>Promise.resolve({error:null}),
    resetPasswordForEmail:email=>{window.__mockClient.resetEmail=email;return Promise.resolve({error:null})},
    resend:payload=>{window.__mockClient.resendEmail=payload.email;return Promise.resolve({error:null})},
    updateUser:()=>Promise.resolve({error:{code:"same_password",message:"New password should be different from the old password."}}),
    signOut:()=>Promise.resolve({error:null})
  },
  from:()=>query(),
  rpc:()=>Promise.resolve({data:[],error:null}),
  storage:{from:()=>({download:()=>Promise.resolve({data:null,error:{message:"not found"}})})}
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

  await page.locator("#authButton").click();
  assert.equal(await page.locator("#authTitle").innerText(),"Вход");
  assert.equal(await page.locator("#authName").count(),0);
  assert.equal(await page.locator("#authPasswordRepeatGroup").isVisible(),false);

  await page.locator("#authSignUpTab").click();
  assert.equal(await page.locator("#authTitle").innerText(),"Регистрация");
  assert.equal(await page.locator("#authPasswordRepeatGroup").isVisible(),true);
  assert.equal(await page.locator("#forgotPasswordButton").isVisible(),false);
  assert.equal(await page.locator("#authPassword").getAttribute("autocomplete"),"new-password");

  await page.locator("#authEmail").fill("student@example.com");
  await page.locator("#authPassword").fill("password-123");
  await page.locator("#authPasswordRepeat").fill("different-123");
  await page.locator("#authSubmitButton").click();
  assert.match(await page.locator("#authMessage").innerText(),/Пароли не совпадают/);

  await page.locator("#authPasswordRepeat").fill("password-123");
  await page.locator("#authSubmitButton").click();
  await page.locator("#siteNotice").waitFor({state:"visible"});
  assert.match(await page.locator("#siteNotice").innerText(),/Регистрация почти завершена/);
  assert.equal(await page.locator("#authModal").isVisible(),false);
  assert.deepEqual(await page.evaluate(()=>window.__mockClient.signupPayload.options),{emailRedirectTo:`http://127.0.0.1:${port}/index.html`});

  await page.locator("#siteNoticeAction").click();
  await page.getByText("Письмо подтверждения отправлено повторно.").waitFor();
  assert.equal(await page.evaluate(()=>window.__mockClient.resendEmail),"student@example.com");

  await page.evaluate(()=>{hideSiteNotice();openAuthModal()});
  await page.locator("#authEmail").fill("student@example.com");
  await page.locator("#forgotPasswordButton").click();
  await page.locator("#siteNotice").waitFor({state:"visible"});
  assert.match(await page.locator("#siteNotice").innerText(),/папку «Спам»/);
  assert.equal(await page.evaluate(()=>window.__mockClient.resetEmail),"student@example.com");

  await page.evaluate(()=>{hideSiteNotice();openPasswordModal()});
  await page.locator("#newPassword").fill("password-123");
  await page.locator("#newPasswordRepeat").fill("password-123");
  await page.getByRole("button",{name:"Сохранить пароль"}).click();
  await page.locator("#siteNotice").waitFor({state:"visible"});
  assert.match(await page.locator("#siteNotice").innerText(),/Этот пароль уже установлен/);
  assert.equal(await page.locator("#passwordModal").isVisible(),false);

  await browser.close();
  server.close();
  console.log("auth-flow browser: all checks passed");
})().catch(error=>{
  server.close();
  console.error(error);
  process.exitCode = 1;
});
