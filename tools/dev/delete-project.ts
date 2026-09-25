// Deletes a throwaway project (e.g. one made by provision.ts).
//   deno run --allow-read --allow-net --allow-env tools/dev/delete-project.ts --ref <ref> --yes
//
// Refuses to delete the dev project named in backend/.env.local.

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { loadEnv, mgmt } from "./lib.ts";

const args = parseArgs(Deno.args, { string: ["ref"], boolean: ["yes"] });
const env = await loadEnv();
if (!args.ref) throw new Error("--ref is required");
if (args.ref === env.ref) throw new Error(`${args.ref} is the dev project in backend/.env.local; not deleting it.`);

const p = await mgmt(env, "GET", `/v1/projects/${args.ref}`);
console.log(`project ${p.ref} "${p.name}" (${p.status}, created ${p.created_at})`);
if (!args.yes) {
  console.log("Pass --yes to delete it.");
  Deno.exit(1);
}
await mgmt(env, "DELETE", `/v1/projects/${args.ref}`);
console.log("deleted");
