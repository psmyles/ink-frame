// Spike (c) and reference for the wizard's "Connect Supabase" step (PLAN.md §6.2
// step 1): Supabase OAuth authorization code + PKCE with a loopback redirect.
//   deno run --allow-read --allow-net --allow-env --allow-run tools/dev/oauth-connect.ts
//
// Needs SUPABASE_OAUTH_CLIENT_ID in backend/.env.local (and SUPABASE_OAUTH_CLIENT_SECRET
// only to compare). Opens the browser for consent, catches the redirect on
// http://localhost:53682/callback, then tries the token exchange without the client
// secret first. Tokens are never printed.

import { mgmt } from "./lib.ts";

const PORT = 53682;
const REDIRECT = `http://localhost:${PORT}/callback`;

const file: Record<string, string> = {};
for (const line of (await Deno.readTextFile(new URL("../../backend/.env.local", import.meta.url))).split("\n")) {
  const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
  if (m) file[m[1]] = m[2];
}
const clientId = Deno.env.get("SUPABASE_OAUTH_CLIENT_ID") ?? file.SUPABASE_OAUTH_CLIENT_ID;
const clientSecret = Deno.env.get("SUPABASE_OAUTH_CLIENT_SECRET") ?? file.SUPABASE_OAUTH_CLIENT_SECRET;
if (!clientId) throw new Error("SUPABASE_OAUTH_CLIENT_ID is missing from backend/.env.local");

const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
const challenge = b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
const state = b64url(crypto.getRandomValues(new Uint8Array(16)));

const authorize = new URL("https://api.supabase.com/v1/oauth/authorize");
authorize.search = new URLSearchParams({
  client_id: clientId,
  response_type: "code",
  redirect_uri: REDIRECT,
  state,
  code_challenge: challenge,
  code_challenge_method: "S256",
}).toString();

// Wait for the browser to come back with ?code=…&state=…
const code = await new Promise<string>((resolve, reject) => {
  const ac = new AbortController();
  Deno.serve({ port: PORT, hostname: "127.0.0.1", signal: ac.signal, onListen() {} }, (req) => {
    const u = new URL(req.url);
    if (u.pathname !== "/callback") return new Response("Not found", { status: 404 });
    queueMicrotask(() => ac.abort());
    const err = u.searchParams.get("error");
    if (err) {
      reject(new Error(`authorize failed: ${err} ${u.searchParams.get("error_description") ?? ""}`));
      return new Response("Authorization failed. You can close this tab.");
    }
    if (u.searchParams.get("state") !== state) {
      reject(new Error("state mismatch"));
      return new Response("State mismatch.", { status: 400 });
    }
    resolve(u.searchParams.get("code") ?? "");
    return new Response("Ink Frame is connected. You can close this tab.");
  });
  console.log("Opening the browser for consent…");
  new Deno.Command("open", { args: [authorize.toString()] }).spawn();
});
console.log(`got an authorization code (${code.length} chars)`);

type Token = { access_token: string; refresh_token: string; expires_in: number; token_type: string };

async function token(params: Record<string, string>, withSecret: boolean) {
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" };
  if (withSecret) headers.Authorization = `Basic ${btoa(`${clientId}:${clientSecret}`)}`;
  const res = await fetch("https://api.supabase.com/v1/oauth/token", {
    method: "POST",
    headers,
    body: new URLSearchParams({ client_id: clientId!, ...params }),
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, json: (() => { try { return JSON.parse(text); } catch { return { raw: text.slice(0, 200) }; } })() };
}

const redact = (j: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(j).map(([k, v]) => [k, /token/.test(k) && typeof v === "string" ? `<${v.length} chars>` : v]));

const codeParams = { grant_type: "authorization_code", code, redirect_uri: REDIRECT, code_verifier: verifier };
let t = await token(codeParams, false);
console.log(`exchange WITHOUT secret → ${t.status}`, JSON.stringify(redact(t.json)));
let secretNeeded = false;
if (!t.ok && clientSecret) {
  secretNeeded = true;
  t = await token(codeParams, true);
  console.log(`exchange WITH secret → ${t.status}`, JSON.stringify(redact(t.json)));
}
if (!t.ok) Deno.exit(1);
const tok = t.json as Token;

const orgs = await mgmt<{ slug: string; name: string }[]>({ token: tok.access_token }, "GET", "/v1/organizations");
console.log(`GET /v1/organizations with the OAuth token → ${orgs.map((o) => o.name).join(", ")}`);
const projects = await mgmt<{ ref: string; name: string }[]>({ token: tok.access_token }, "GET", "/v1/projects");
console.log(`GET /v1/projects → ${projects.map((p) => p.name).join(", ")}`);

const refreshParams = { grant_type: "refresh_token", refresh_token: tok.refresh_token };
let r = await token(refreshParams, secretNeeded);
console.log(`refresh ${secretNeeded ? "WITH" : "WITHOUT"} secret → ${r.status}`, JSON.stringify(redact(r.json)));
if (!r.ok && !secretNeeded && clientSecret) {
  r = await token(refreshParams, true);
  console.log(`refresh WITH secret → ${r.status}`, JSON.stringify(redact(r.json)));
}
