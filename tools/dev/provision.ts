// Creates and sets up a family project end to end through the Management API: the
// reference implementation of the app's setup wizard (PLAN.md §6.2). Use it for
// throwaway test projects in the spare free slot.
//   deno run --allow-read --allow-net --allow-env tools/dev/provision.ts --name <name>
//     [--region ap-south-1] [--keep-email]
//
// Optional env: GOOGLE_CLIENT_IDS (comma-separated; the first is the main one) and
// APPLE_CLIENT_IDS (bundle ids). Email sign-in is turned off unless --keep-email
// (the integration tests need it). Prints the new ref; the DB password is not kept.

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { deployFunctions } from "./deploy-functions.ts";
import { loadEnv, mgmt } from "./lib.ts";
import { applyMigrations } from "./migrate.ts";

const args = parseArgs(Deno.args, { string: ["name", "region"], boolean: ["keep-email"], default: { region: "ap-south-1" } });
if (!args.name) throw new Error("--name is required");

const { token } = await loadEnv();
const t0 = Date.now();
const lap = (what: string) => console.log(`[${((Date.now() - t0) / 1000).toFixed(0)}s] ${what}`);

const orgs = await mgmt<{ slug: string; name: string }[]>({ token }, "GET", "/v1/organizations");
const org = orgs[0];
const dbPass = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(24))));

const project = await mgmt<{ ref: string; status: string }>({ token }, "POST", "/v1/projects", {
  name: args.name,
  organization_slug: org.slug,
  db_pass: dbPass,
  region_selection: { type: "specific", code: args.region },
});
const env = { token, ref: project.ref };
lap(`created ${project.ref} in ${org.name} (${project.status})`);

// Wait until the project and the services the wizard needs are up.
for (let i = 0; ; i++) {
  const p = await mgmt(env, "GET", `/v1/projects/${env.ref}`);
  if (p.status === "ACTIVE_HEALTHY") {
    const health = await mgmt<{ name: string; healthy: boolean }[]>(env, "GET",
      `/v1/projects/${env.ref}/health?services=db,auth,rest,storage`).catch(() => []);
    if (health.length && health.every((h) => h.healthy)) break;
  }
  if (i > 120) throw new Error(`project not healthy after 10 min: ${p.status}`);
  await new Promise((r) => setTimeout(r, 5000));
}
lap("healthy");

await applyMigrations(env);
lap("migrations applied");

await deployFunctions(env);
lap("functions deployed");

const split = (v?: string) => (v ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const google = split(Deno.env.get("GOOGLE_CLIENT_IDS"));
const apple = split(Deno.env.get("APPLE_CLIENT_IDS"));
const auth: Record<string, unknown> = {};
if (!args["keep-email"]) auth.external_email_enabled = false;
if (google.length) {
  Object.assign(auth, {
    external_google_enabled: true,
    external_google_client_id: google[0],
    external_google_additional_client_ids: google.slice(1).join(",") || null,
  });
}
if (apple.length) {
  Object.assign(auth, {
    external_apple_enabled: true,
    external_apple_client_id: apple[0],
    external_apple_additional_client_ids: apple.slice(1).join(",") || null,
  });
}
if (Object.keys(auth).length) {
  await mgmt(env, "PATCH", `/v1/projects/${env.ref}/config/auth`, auth);
  lap(`auth configured: ${Object.keys(auth).join(", ")}`);
}

console.log(`\nref ${env.ref}\nurl https://${env.ref}.supabase.co`);
