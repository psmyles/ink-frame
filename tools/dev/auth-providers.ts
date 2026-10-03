// Turns on Google and Apple sign-in on the project in backend/.env.local with the IDs
// in shared/oauth-clients.json (what provision.ts does for a new project). Email
// sign-in is left as it is.
//   deno run --allow-read --allow-net --allow-env tools/dev/auth-providers.ts [--check]

import { authProviders, loadEnv, mgmt } from "./lib.ts";

const env = await loadEnv();
const want = await authProviders();
if (!Deno.args.includes("--check")) await mgmt(env, "PATCH", `/v1/projects/${env.ref}/config/auth`, want);
const now = await mgmt<Record<string, unknown>>(env, "GET", `/v1/projects/${env.ref}/config/auth`);
let ok = true;
for (const [k, v] of Object.entries(want)) {
  const same = String(now[k] ?? null) === String(v ?? null);
  ok &&= same;
  console.log(`${same ? "✓" : "✗"} ${k} = ${now[k]}`);
}
console.log(`email sign-in: ${now.external_email_enabled ? "on" : "off"}`);
if (!ok) Deno.exit(1);
