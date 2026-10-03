// Creates and sets up a frame's project end to end through the Management API: the
// reference implementation of the app's setup wizard (PLAN.md §6.2). Use it for
// throwaway test projects in the spare free slot.
//   deno run --allow-read --allow-net --allow-env tools/dev/provision.ts --name <name>
//     [--frame-name "Kitchen"] [--model reterminal-e1002] [--timezone Europe/Berlin]
//     [--region ap-south-1] [--keep-email] [--no-frame]
//
// Google/Apple sign-in come from shared/oauth-clients.json. Email sign-in is turned off unless --keep-email
// (the integration tests need it). Describes the frame like the wizard does, unless
// --no-frame (the integration tests set up their own). Prints the new ref; the DB
// password is not kept. The owner is added when they first sign in (the app).

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { deployFunctions } from "./deploy-functions.ts";
import { authProviders, loadEnv, mgmt, sql } from "./lib.ts";
import { applyMigrations } from "./migrate.ts";

const args = parseArgs(Deno.args, {
  string: ["name", "region", "frame-name", "model", "timezone"],
  boolean: ["keep-email", "no-frame"],
  default: { region: "ap-south-1", model: "reterminal-e1002", timezone: "UTC" },
});
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

if (!args["no-frame"]) {
  const q = (v: string) => `'${v.replaceAll("'", "''")}'`;
  await sql(env, `select private.setup_frame(${q(args["frame-name"] ?? args.name)}, ${q(args.model)}, ${q(args.timezone)})`);
  lap(`frame described: ${args.model}, ${args.timezone}`);
}

await deployFunctions(env);
lap("functions deployed");

const auth: Record<string, unknown> = await authProviders();
// Dev projects keep email/password sign-in (tests, and the app's dev mode) without confirmation mails.
if (args["keep-email"]) auth.mailer_autoconfirm = true;
else auth.external_email_enabled = false;
if (Object.keys(auth).length) {
  await mgmt(env, "PATCH", `/v1/projects/${env.ref}/config/auth`, auth);
  lap(`auth configured: ${Object.keys(auth).join(", ")}`);
}

console.log(`\nref ${env.ref}\nurl https://${env.ref}.supabase.co`);
