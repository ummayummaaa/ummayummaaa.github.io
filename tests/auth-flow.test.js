const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname,"..","index.html"),"utf8");

assert.match(html,/id="authSignInTab"[\s\S]*id="authSignUpTab"/);
assert.match(html,/function setAuthMode\(mode\)/);
assert.match(html,/id="authPasswordRepeat"/);
assert.match(html,/if\(password !== repeated\)/);
assert.doesNotMatch(html,/id="authName"|display_name:displayName/);

assert.match(html,/Регистрация почти завершена\. Мы отправили письмо на указанный email\./);
assert.match(html,/Если аккаунт с таким email существует, мы отправили ссылку для восстановления пароля\./);
assert.match(html,/actionLabel:"Отправить ещё раз"/);

assert.match(html,/error\.code === "same_password"/);
assert.match(html,/Этот пароль уже установлен для вашего аккаунта\. Вы можете продолжить вход с ним\./);

assert.match(html,/function setButtonBusy\(button,busy,busyText=""\)/);
assert.match(html,/\.action:active/);
assert.match(html,/\.action:focus-visible/);
assert.match(html,/signInWithOAuth\(\{/);
assert.match(html,/resetPasswordForEmail\(email,/);
assert.match(html,/auth\.resend\(\{type:"signup"/);

console.log("auth-flow: all checks passed");
