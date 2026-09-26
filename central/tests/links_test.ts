import { assertEquals } from "jsr:@std/assert@1";
import { oauthTarget, parseJoin, platformOf } from "../site/assets/links.js";

const U1 = "https://vrhsxzedzhvujnirsuhg.supabase.co";
const U2 = "https://abcdefghijklmnopqrst.supabase.co";
const K1 = "sb_publishable_AbCdEf0123456789_xyz";
const K2 = "sb_publishable_ZyXwVu9876543210_abc";

Deno.test("invite link", () => {
  const r = parseJoin(`#u=${encodeURIComponent(U1)}&k=${K1}&c=AbC123xyz`);
  assertEquals(r?.frames, [{ url: U1, key: K1 }]);
  assertEquals(r?.code, "AbC123xyz");
  assertEquals(r?.appUrl, `inkframe://join?u=${encodeURIComponent(U1)}&k=${K1}&c=AbC123xyz`);
});

Deno.test("another-device link with two frames, no code", () => {
  const r = parseJoin(`u=${U1}&k=${K1}&u=${U2}/&k=${K2}`);
  assertEquals(r?.frames, [{ url: U1, key: K1 }, { url: U2, key: K2 }]);
  assertEquals(r?.code, null);
});

Deno.test("legacy anon JWT keys are accepted", () => {
  const jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.sig_abc-DEF";
  assertEquals(parseJoin(`u=${U1}&k=${jwt}`)?.frames[0].key, jwt);
});

Deno.test("broken links are rejected", () => {
  for (const bad of [
    "",
    `u=${U1}`, // no key
    `u=${U1}&k=${K1}&k=${K2}`, // counts differ
    `u=https://evil.example.com&k=${K1}`, // not a Supabase project
    `u=http://vrhsxzedzhvujnirsuhg.supabase.co&k=${K1}`, // not https
    `u=${U1}&k=javascript:alert(1)`,
    `u=${U1}&k=${K1}&c=<script>`,
    `u=${U1}&k=${K1}&u=${U2}&k=${K2}&c=AbC123xyz`, // a code with several frames
    `u=${U1}&k=${K1}&c=AbC123xyz&c=Other12345`,
  ]) assertEquals(parseJoin(bad), null, bad);
});

Deno.test("oauth callback is forwarded without extra params", () => {
  assertEquals(oauthTarget("?code=abc&state=xyz&utm=1"), "inkframe://supabase-oauth?code=abc&state=xyz");
  assertEquals(
    oauthTarget("?error=access_denied&error_description=User+denied"),
    "inkframe://supabase-oauth?error=access_denied&error_description=User+denied",
  );
  assertEquals(oauthTarget("?code=abc"), null);
  assertEquals(oauthTarget(""), null);
});

Deno.test("platform", () => {
  assertEquals(platformOf("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"), "ios");
  assertEquals(platformOf("Mozilla/5.0 (Linux; Android 15; Pixel 9)"), "android");
  assertEquals(platformOf("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"), "desktop");
});
