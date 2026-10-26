const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const {chromium} = require("playwright");

// Use the real Supabase browser SDK, with an isolated simulated auth server.
// Download the SDK from the URL in index.html and pass its path as SUPABASE_SDK_PATH.
const sdk = fs.readFileSync(process.env.SUPABASE_SDK_PATH,"utf8");
const root = path.resolve(__dirname,"..");
const storageKey = "sb-hfgiknokcjrwyddflmtq-auth-token";
const user = {id:"11111111-1111-4111-8111-111111111111",email:"session-test@example.com",
  aud:"authenticated",role:"authenticated",app_metadata:{provider:"email"},
  user_metadata:{display_name:"Session Test"},created_at:"2026-01-01T00:00:00Z"};
function session(expired=false){
  const now = Math.floor(Date.now()/1000);
  const expires = now + (expired ? -3600 : 3600);
  const payload = {sub:user.id,aud:"authenticated",role:"authenticated",iat:now-7200,exp:expires};
  const token = [Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url"),
    Buffer.from(JSON.stringify(payload)).toString("base64url"),"test-signature"].join(".");
  return {access_token:token,refresh_token:"test-refresh-token",token_type:"bearer",
    expires_in:3600,expires_at:expires,user};
}
const server = http.createServer((req,res)=>{
  const filename = path.join(root,req.url.split("?")[0] === "/" ? "index.html" : req.url.split("?")[0]);
  if(!filename.startsWith(root + path.sep) || !fs.existsSync(filename)) {res.writeHead(404).end();return;}
  res.setHeader("Content-Type",filename.endsWith(".js") ? "application/javascript" : "text/html");
  fs.createReadStream(filename).pipe(res);
});
(async()=>{
  await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({headless:true,executablePath:"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"});
  try{
    let refreshes = 0;
    let logoutScope = "";
    const context = await browser.newContext({storageState:{cookies:[],origins:[{origin,
      localStorage:[{name:storageKey,value:JSON.stringify(session(true))}]}]}});
    await context.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",r=>r.fulfill({contentType:"application/javascript",body:sdk}));
    await context.route("https://cdnjs.cloudflare.com/ajax/libs/pdf.js/**",r=>r.fulfill({contentType:"application/javascript",body:"window.pdfjsLib={GlobalWorkerOptions:{}};"}));
    await context.route("https://hfgiknokcjrwyddflmtq.supabase.co/**",route=>{
      const url = new URL(route.request().url());
      let body = [];
      if(url.pathname === "/auth/v1/token"){
        assert.equal(url.searchParams.get("grant_type"),"refresh_token");
        refreshes++;
        body = session();
        body.refresh_token = "rotated-refresh-token-" + refreshes;
      }else if(url.pathname === "/auth/v1/logout"){
        logoutScope = url.searchParams.get("scope");
        return route.fulfill({status:204});
      }else if(url.pathname === "/auth/v1/user") body = user;
      else if(url.pathname === "/rest/v1/medquiz_profiles") body = {is_admin:false,account_status:"active",access_type:"free"};
      return route.fulfill({status:200,contentType:"application/json",headers:{"content-range":"0-0/0"},body:JSON.stringify(body)});
    });
    let page = await context.newPage();
    const errors = [];
    page.on("pageerror",error=>errors.push(error.message));
    await page.goto(origin,{waitUntil:"load"});
    await page.getByText("Добрый день, Session Test!",{exact:true}).waitFor();
    assert.equal(refreshes,1,"expired access token must renew using the saved refresh token");
    assert.equal(await page.evaluate(key=>JSON.parse(localStorage.getItem(key)).refresh_token,storageKey),"rotated-refresh-token-1");
    await page.reload();
    await page.getByText("Добрый день, Session Test!",{exact:true}).waitFor();
    await page.close();
    page = await context.newPage();
    await page.goto(origin,{waitUntil:"load"});
    await page.getByText("Добрый день, Session Test!",{exact:true}).waitFor();
    // Reopen the browser with its persisted storage, just as a regular profile does.
    const state = await context.storageState();
    await page.evaluate(()=>{
      window.__originalGetSession = supabaseClient.auth.getSession.bind(supabaseClient.auth);
      supabaseClient.auth.getSession = async()=>({data:{session:null},error:new Error("temporary offline")});
      window.dispatchEvent(new Event("online"));
    });
    await page.waitForFunction(()=>sessionRestorePromise === null);
    assert.equal(await page.locator("#profileName").innerText(),"Session Test");
    await page.evaluate(()=>{
      supabaseClient.auth.getSession = window.__originalGetSession;
      window.dispatchEvent(new Event("online"));
    });
    await page.waitForFunction(()=>sessionRestorePromise === null);
    const reopened = await browser.newContext({storageState:state});
    await reopened.route("**/*",async route=>{
      const url = route.request().url();
      if(url.includes("cdn.jsdelivr.net/npm/@supabase/supabase-js@2")) return route.fulfill({contentType:"application/javascript",body:sdk});
      if(url.includes("cdnjs.cloudflare.com/ajax/libs/pdf.js/")) return route.fulfill({contentType:"application/javascript",body:"window.pdfjsLib={GlobalWorkerOptions:{}};"});
      if(url.includes("supabase.co/")) return route.fulfill({status:200,contentType:"application/json",body:"[]"});
      return route.continue();
    });
    const reopenedPage = await reopened.newPage();
    await reopenedPage.goto(origin,{waitUntil:"load"});
    await reopenedPage.getByText("Добрый день, Session Test!",{exact:true}).waitFor();
    await reopened.close();
    page.once("dialog",dialog=>dialog.accept());
    await page.locator("#authButton").click();
    await page.getByText("Добрый день!",{exact:true}).waitFor();
    assert.equal(logoutScope,"local","logout must not revoke sessions on other devices");
    assert.equal(await page.evaluate(key=>localStorage.getItem(key),storageKey),null);
    await page.reload();
    await page.getByText("Добрый день!",{exact:true}).waitFor();
    assert.deepEqual(errors,[]);
    await context.close();
    console.log("session persistence: expiry renewal, reload, reopen, offline recovery and explicit logout passed");
  }finally{
    await browser.close();
    await new Promise(resolve=>server.close(resolve));
  }
})().catch(error=>{server.close();console.error(error);process.exitCode=1;});
