// Spike (c) and reference for the wizard's "Connect Supabase" step (PLAN.md §6.2
// step 1): Supabase OAuth authorization code + PKCE with a loopback redirect.
//   deno run --allow-read --allow-net --allow-env --allow-run tools/dev/oauth-connect.ts [--print-url]
//   (--print-url: print the consent link instead of opening it, e.g. for a private
//    window signed in as another Supabase account)
//
// Opens the browser for consent, catches the redirect on http://localhost:53682/callback,
// then exchanges the code and refreshes through the Cloudflare Worker, like the app
// (--direct: with SUPABASE_OAUTH_CLIENT_SECRET from backend/.env.local instead). The
// client ID comes from shared/oauth-clients.json. Tokens are never printed.

import { mgmt } from "./lib.ts";

const PORT = 53682;
const REDIRECT = `http://localhost:${PORT}/callback`;

const file: Record<string, string> = {};
for (const line of (await Deno.readTextFile(new URL("../../backend/.env.local", import.meta.url))).split("\n")) {
  const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
  if (m) file[m[1]] = m[2];
}
const shared = JSON.parse(await Deno.readTextFile(new URL("../../shared/oauth-clients.json", import.meta.url)));
const clientId: string = shared.supabase.clientId;
const clientSecret = Deno.env.get("SUPABASE_OAUTH_CLIENT_SECRET") ?? file.SUPABASE_OAUTH_CLIENT_SECRET;

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
  if (Deno.args.includes("--print-url")) {
    console.log(`Open this in a private window and approve:\n${authorize}`);
  } else {
    console.log("Opening the browser for consent…");
    new Deno.Command("open", { args: [authorize.toString()] }).spawn();
  }
});
console.log(`got an authorization code (${code.length} chars)`);

type Token = { access_token: string; refresh_token: string; expires_in: number; token_type: string };

// Like the app: the code exchange and refresh go through the Cloudflare Worker, which
// adds the client secret (shared/api/directory.yaml). --direct uses the secret from
// backend/.env.local instead (spike c's original check).
const DIRECTORY = Deno.env.get("DIRECTORY_URL") ?? "https://ink-frame-directory.psmyles.workers.dev";
const direct = Deno.args.includes("--direct");

async function token(params: Record<string, string>) {
  const res = direct
    ? await fetch("https://api.supabase.com/v1/oauth/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      },
      body: new URLSearchParams({ client_id: clientId!, ...params }),
    })
    : await fetch(`${DIRECTORY}/v1/supabase-oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });
  const text = await res.text();
  return { ok: res.ok, status: res.status, json: (() => { try { return JSON.parse(text); } catch { return { raw: text.slice(0, 200) }; } })() };
}

const redact = (j: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(j).map(([k, v]) => [k, /token/.test(k) && typeof v === "string" ? `<${v.length} chars>` : v]));

const t = await token({ grant_type: "authorization_code", code, redirect_uri: REDIRECT, code_verifier: verifier });
console.log(`exchange ${direct ? "with the secret" : "through the Worker"} → ${t.status}`, JSON.stringify(redact(t.json)));
if (!t.ok) Deno.exit(1);
const tok = t.json as Token;

const orgs = await mgmt<{ slug: string; name: string }[]>({ token: tok.access_token }, "GET", "/v1/organizations");
console.log(`GET /v1/organizations with the OAuth token → ${orgs.map((o) => o.name).join(", ")}`);
const projects = await mgmt<{ ref: string; name: string }[]>({ token: tok.access_token }, "GET", "/v1/projects");
console.log(`GET /v1/projects → ${projects.map((p) => p.name).join(", ")}`);

const r = await token({ grant_type: "refresh_token", refresh_token: tok.refresh_token });
console.log(`refresh ${direct ? "with the secret" : "through the Worker"} → ${r.status}`, JSON.stringify(redact(r.json)));
