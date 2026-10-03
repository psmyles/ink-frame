// The directory against SQLite, with ID tokens signed by a test key standing in for
// Google's and Apple's.
//   deno test --allow-read central/directory/

import { assert, assertEquals, assertMatch, assertNotEquals } from "jsr:@std/assert@1";
import clients from "../../../shared/oauth-clients.json" with { type: "json" };
import { directory, MAX_FRAMES, MAX_TOKENS, purgeTokens, TOKEN_MAX_IDLE_S } from "../src/directory.ts";
import { IdTokenVerifier, type Jwk, type Provider } from "../src/id_token.ts";
import { testDb } from "./d1.ts";

const ISS = { google: "https://accounts.google.com", apple: "https://appleid.apple.com" };
const AUD = { google: clients.google.web, ios: clients.google.ios, apple: clients.apple.bundleId };
const U1 = "https://vrhsxzedzhvujnirsuhg.supabase.co";
const U2 = "https://abcdefghijklmnopqrst.supabase.co";
const U3 = "https://zyxwvutsrqponmlkjihg.supabase.co";
const K1 = "sb_publishable_AbCdEf0123456789_xyz";
const K2 = "sb_publishable_ZyXwVu9876543210_abc";

const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));

async function keyPair(kid: string) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pub = await crypto.subtle.exportKey("jwk", pair.publicKey);
  return { kid, privateKey: pair.privateKey, jwk: { kty: "RSA", kid, n: pub.n, e: pub.e } as Jwk };
}

const KEY = await keyPair("k1");
const OTHER = await keyPair("k1"); // same key ID, different key

async function idToken(claims: Record<string, unknown>, key = KEY, header: Record<string, unknown> = {}) {
  const head = enc({ alg: "RS256", kid: key.kid, typ: "JWT", ...header });
  const body = enc(claims);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(new Uint8Array(sig))}`;
}

function setup(keys: Jwk[] = [KEY.jwk]) {
  let clock = Date.UTC(2026, 9, 3, 12);
  let fetches = 0;
  const source = (_p: Provider) => {
    fetches++;
    return Promise.resolve(keys);
  };
  const verifier = new IdTokenVerifier(
    { google: Object.values(clients.google), apple: [clients.apple.bundleId] },
    source,
    () => clock,
  );
  const db = testDb();
  const handle = directory({ db, verifier, now: () => clock });
  const nowS = () => Math.floor(clock / 1000);

  async function call(method: string, path: string, opts: { token?: string; body?: unknown } = {}) {
    const res = await handle(new Request(`https://dir.test/v1${path}`, {
      method,
      headers: opts.token ? { Authorization: `Bearer ${opts.token}` } : {},
      body: opts.body === undefined ? undefined : typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body),
    }));
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }

  const google = (sub: string, extra: Record<string, unknown> = {}) =>
    idToken({ iss: ISS.google, aud: AUD.google, sub, iat: nowS(), exp: nowS() + 3600, ...extra });
  const apple = (sub: string) => idToken({ iss: ISS.apple, aud: AUD.apple, sub, iat: nowS(), exp: nowS() + 600 });

  async function signIn(token: string | Promise<string>) {
    const r = await call("POST", "/sign-in", { body: { id_token: await token } });
    assertEquals(r.status, 200, JSON.stringify(r.body));
    return r.body as { token: string; frames: { url: string; key: string }[] };
  }

  return {
    db,
    call,
    google,
    apple,
    signIn,
    tick: (ms: number) => (clock += ms),
    now: () => clock,
    fetches: () => fetches,
  };
}

Deno.test("a new account signs in with no frames; adds, re-adds and removes them", async () => {
  const t = setup();
  const s = await t.signIn(t.google("alice"));
  assertMatch(s.token, /^ifd_[A-Za-z0-9_-]{43}$/);
  assertEquals(s.frames, []);

  let r = await t.call("POST", "/frames", { token: s.token, body: { add: [{ url: U1, key: K1 }] } });
  assertEquals(r.status, 200);
  t.tick(1000);
  r = await t.call("POST", "/frames", { token: s.token, body: { add: [{ url: U2, key: K2 }] } });
  assertEquals(r.body.frames, [{ url: U1, key: K1 }, { url: U2, key: K2 }]);

  // Adding again updates the key and keeps the order (oldest first).
  r = await t.call("POST", "/frames", { token: s.token, body: { add: [{ url: U1, key: K2 }] } });
  assertEquals(r.body.frames, [{ url: U1, key: K2 }, { url: U2, key: K2 }]);

  r = await t.call("POST", "/frames", { token: s.token, body: { remove: [U1, U3] } });
  assertEquals(r.body.frames, [{ url: U2, key: K2 }]);
  assertEquals((await t.call("GET", "/frames", { token: s.token })).body, { frames: [{ url: U2, key: K2 }] });
});

Deno.test("a new device with the same Google account finds the frames", async () => {
  const t = setup();
  const phone = await t.signIn(t.google("alice"));
  await t.call("POST", "/frames", { token: phone.token, body: { add: [{ url: U1, key: K1 }] } });

  // The iPhone's token has the iOS client ID as audience.
  const mac = await t.signIn(t.google("alice", { aud: AUD.ios }));
  assertNotEquals(mac.token, phone.token);
  assertEquals(mac.frames, [{ url: U1, key: K1 }]);

  // Someone else sees nothing; an Apple account with the same sub is another account.
  assertEquals((await t.signIn(t.google("bob"))).frames, []);
  assertEquals((await t.signIn(t.apple("alice"))).frames, []);
});

Deno.test("only hashes are stored, not the account ID or the token", async () => {
  const t = setup();
  const s = await t.signIn(t.google("alice-sub-123"));
  await t.call("POST", "/frames", { token: s.token, body: { add: [{ url: U1, key: K1 }] } });
  const dump = JSON.stringify([
    t.db.raw.prepare("select * from frames").all(),
    t.db.raw.prepare("select * from tokens").all(),
  ]);
  assert(!dump.includes("alice-sub-123"));
  assert(!dump.includes(s.token));
  assertMatch(dump, /"account":"[0-9a-f]{64}"/);
});

Deno.test("ID tokens that aren't ours, or are forged or expired, are refused", async () => {
  const t = setup();
  const now = Math.floor(Date.UTC(2026, 9, 3, 12) / 1000);
  const base = { iss: ISS.google, aud: AUD.google, sub: "alice", iat: now, exp: now + 3600 };
  const cases: [string, string][] = [
    ["expired", await idToken({ ...base, exp: now - 120 })],
    ["another app's client ID", await idToken({ ...base, aud: "123-other.apps.googleusercontent.com" })],
    ["Apple token for a Google client ID", await idToken({ ...base, iss: ISS.apple })],
    ["unknown issuer", await idToken({ ...base, iss: "https://evil.example" })],
    ["forged with another key", await idToken(base, OTHER)],
    ["unknown key ID", await idToken(base, { ...KEY, kid: "k9" })],
    ["alg none", (await idToken(base, KEY, { alg: "none" })).replace(/\.[^.]+$/, ".")],
    ["no subject", await idToken({ ...base, sub: "" })],
    ["issued in the future", await idToken({ ...base, iat: now + 3600, exp: now + 7200 })],
    ["garbage", "not.a.jwt"],
  ];
  for (const [name, token] of cases) {
    const r = await t.call("POST", "/sign-in", { body: { id_token: token } });
    assertEquals([name, r.status, r.body?.error?.code], [name, 401, "invalid_id_token"]);
  }
  for (const body of [{}, { id_token: 42 }, "not json", "[1]"]) {
    assertEquals((await t.call("POST", "/sign-in", { body })).body.error.code, "bad_request");
  }
});

Deno.test("device tokens: required, signed out, and forgotten with the account", async () => {
  const t = setup();
  for (const token of [undefined, "nope", "ifd_" + "A".repeat(43)]) {
    const r = await t.call("GET", "/frames", { token });
    assertEquals([r.status, r.body.error.code], [401, "invalid_token"]);
  }
  const phone = await t.signIn(t.google("alice"));
  const mac = await t.signIn(t.google("alice"));
  await t.call("POST", "/frames", { token: phone.token, body: { add: [{ url: U1, key: K1 }] } });

  assertEquals((await t.call("POST", "/sign-out", { token: mac.token })).status, 204);
  assertEquals((await t.call("GET", "/frames", { token: mac.token })).status, 401);
  assertEquals((await t.call("GET", "/frames", { token: phone.token })).body.frames.length, 1);

  const another = await t.signIn(t.google("alice"));
  assertEquals((await t.call("DELETE", "/me", { token: phone.token })).status, 204);
  assertEquals((await t.call("GET", "/frames", { token: phone.token })).status, 401);
  assertEquals((await t.call("GET", "/frames", { token: another.token })).status, 401);
  assertEquals((await t.signIn(t.google("alice"))).frames, []);
});

Deno.test("invalid addresses and too many frames", async () => {
  const t = setup();
  const s = await t.signIn(t.google("alice"));
  for (const body of [
    { add: [{ url: "https://example.com", key: K1 }] },
    { add: [{ url: U1, key: "secret_key" }] },
    { add: [{ url: `${U1}/`, key: K1 }] },
    { remove: ["https://example.com"] },
    { add: { url: U1, key: K1 } },
    "x".repeat(17 * 1024),
  ]) {
    const r = await t.call("POST", "/frames", { token: s.token, body });
    assertEquals([r.status, r.body.error.code], [400, "bad_request"]);
  }

  const frames = (from: number, n: number) =>
    Array.from({ length: n }, (_, i) => ({ url: `https://${String(from + i).padStart(20, "a")}.supabase.co`, key: K1 }));
  assertEquals((await t.call("POST", "/frames", { token: s.token, body: { add: frames(0, MAX_FRAMES) } })).status, 200);
  const r = await t.call("POST", "/frames", { token: s.token, body: { add: frames(100, 1) } });
  assertEquals([r.status, r.body.error.code], [409, "too_many_frames"]);
  // Removing one makes room in the same call.
  const swap = { remove: [frames(0, 1)[0].url], add: frames(100, 1) };
  assertEquals((await t.call("POST", "/frames", { token: s.token, body: swap })).body.frames.length, MAX_FRAMES);
});

Deno.test("an account keeps its newest device tokens; idle ones expire", async () => {
  const t = setup();
  const tokens = [];
  for (let i = 0; i <= MAX_TOKENS; i++) {
    tokens.push((await t.signIn(t.google("alice"))).token);
    t.tick(1000);
  }
  assertEquals((await t.call("GET", "/frames", { token: tokens[0] })).status, 401);
  assertEquals((await t.call("GET", "/frames", { token: tokens[1] })).status, 200);

  // Use keeps a token alive (used_at moves at most daily); idle ones are purged.
  t.tick((TOKEN_MAX_IDLE_S - 2 * 86400) * 1000);
  assertEquals((await t.call("GET", "/frames", { token: tokens[2] })).status, 200);
  t.tick(3 * 86400 * 1000);
  await purgeTokens(t.db, t.now());
  assertEquals((await t.call("GET", "/frames", { token: tokens[2] })).status, 200);
  assertEquals((await t.call("GET", "/frames", { token: tokens[3] })).status, 401);
});

Deno.test("provider keys are cached, and refetched when they rotate", async () => {
  const NEW = await keyPair("k2");
  const t = setup([KEY.jwk, NEW.jwk]);
  await t.signIn(t.google("a"));
  await t.signIn(t.google("b"));
  assertEquals(t.fetches(), 1);

  // A token with an unknown key ID refetches, but at most once a minute.
  const now = Math.floor(Date.UTC(2026, 9, 3, 12) / 1000);
  const unknown = await idToken({ iss: ISS.google, aud: AUD.google, sub: "a", iat: now, exp: now + 3600 }, { ...KEY, kid: "k3" });
  await t.call("POST", "/sign-in", { body: { id_token: unknown } });
  assertEquals(t.fetches(), 1);
  t.tick(61_000);
  await t.call("POST", "/sign-in", { body: { id_token: unknown } });
  assertEquals(t.fetches(), 2);

  t.tick(3600_000 + 1);
  await t.signIn(idToken({ iss: ISS.google, aud: AUD.google, sub: "a", iat: now + 3700, exp: now + 7200 }, NEW));
  assertEquals(t.fetches(), 3);
});

Deno.test("unknown routes", async () => {
  const t = setup();
  for (const [m, p] of [["GET", "/"], ["GET", "/sign-in"], ["PUT", "/frames"], ["POST", "/me"]]) {
    assertEquals((await t.call(m, p)).status, 404);
  }
});

// ── Supabase OAuth token exchange (the client secret stays in the Worker) ──

function oauthSetup(answer: (body: URLSearchParams) => Response | Promise<Response>, secret: string | null = "sba_secret") {
  const sent: { url: string; auth: string | null; body: URLSearchParams }[] = [];
  const fakeFetch = (async (url: string | URL | Request, init?: RequestInit) => {
    const body = new URLSearchParams(init?.body as URLSearchParams);
    sent.push({ url: String(url), auth: new Headers(init?.headers).get("Authorization"), body });
    return answer(body);
  }) as typeof fetch;
  const handle = directory({
    db: testDb(),
    verifier: { verify: () => Promise.reject(new Error("unused")) },
    oauth: { ...clients.supabase, clientSecret: secret ?? undefined },
    fetch: fakeFetch,
  });
  const call = async (body: unknown) => {
    const res = await handle(new Request("https://dir.test/v1/supabase-oauth/token", { method: "POST", body: JSON.stringify(body) }));
    return { status: res.status, body: await res.json() };
  };
  return { sent, call };
}

const TOKENS = { access_token: "sbp_oauth_access", refresh_token: "refresh", expires_in: 86400, token_type: "Bearer", extra: "dropped" };
const CODE = { grant_type: "authorization_code", code: "c0de", code_verifier: "v".repeat(43), redirect_uri: clients.supabase.redirectUris[1] };

Deno.test("Supabase OAuth: the code is exchanged with the secret added", async () => {
  const t = oauthSetup(() => Response.json(TOKENS));
  const r = await t.call(CODE);
  assertEquals(r.status, 200);
  assertEquals(r.body, { access_token: "sbp_oauth_access", refresh_token: "refresh", expires_in: 86400, token_type: "Bearer" });
  assertEquals(t.sent[0].url, "https://api.supabase.com/v1/oauth/token");
  assertEquals(t.sent[0].auth, `Basic ${btoa(`${clients.supabase.clientId}:sba_secret`)}`);
  assertEquals(Object.fromEntries(t.sent[0].body), { client_id: clients.supabase.clientId, ...CODE });

  const refresh = await t.call({ grant_type: "refresh_token", refresh_token: "refresh" });
  assertEquals(refresh.status, 200);
  assertEquals(Object.fromEntries(t.sent[1].body), { client_id: clients.supabase.clientId, grant_type: "refresh_token", refresh_token: "refresh" });
});

Deno.test("Supabase OAuth: refusals, bad requests and outages", async () => {
  const refused = oauthSetup(() => Response.json({ message: "Invalid code" }, { status: 400 }));
  assertEquals((await refused.call(CODE)).body.error, { code: "oauth_failed", message: "Invalid code" });

  const down = oauthSetup(() => new Response("", { status: 503 }));
  assertEquals((await down.call(CODE)).status, 502);

  const t = oauthSetup(() => Response.json(TOKENS));
  for (const body of [
    { ...CODE, redirect_uri: "https://evil.example/callback" },
    { ...CODE, code_verifier: "short" },
    { ...CODE, grant_type: "client_credentials" },
    { grant_type: "refresh_token" },
  ]) {
    const r = await t.call(body);
    assertEquals([r.status, r.body.error.code], [400, "bad_request"]);
  }
  assertEquals(t.sent.length, 0);

  const unset = oauthSetup(() => Response.json(TOKENS), null);
  assertEquals((await unset.call(CODE)).status, 503);
});
