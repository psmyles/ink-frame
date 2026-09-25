// Deploys device-api and app-api through the Management API's multipart deploy
// endpoint (server-side bundling), the way the app's setup wizard will
// (PLAN.md §6.2 step 4). No CLI or Docker involved.
//   deno run --allow-read --allow-net --allow-env tools/dev/deploy-functions.ts
//
// Each function is uploaded as its own folder plus _shared/, with paths relative to
// backend/supabase/functions so `../_shared/x.ts` imports resolve.

import { type Env, loadEnv, mgmt } from "./lib.ts";

export const FUNCTIONS = ["device-api", "app-api"];
const functionsDir = new URL("../../backend/supabase/functions/", import.meta.url);

async function sources(dir: string): Promise<string[]> {
  const out: string[] = [];
  for await (const e of Deno.readDir(new URL(`${dir}/`, functionsDir))) {
    if (e.isFile && e.name.endsWith(".ts")) out.push(`${dir}/${e.name}`);
  }
  return out.sort();
}

export async function deployFunctions(env: Env): Promise<void> {
  const shared = await sources("_shared");
  for (const slug of FUNCTIONS) {
    const form = new FormData();
    form.append("metadata", JSON.stringify({ entrypoint_path: `${slug}/index.ts`, name: slug, verify_jwt: false }));
    for (const path of [...(await sources(slug)), ...shared]) {
      const bytes = await Deno.readFile(new URL(path, functionsDir));
      form.append("file", new Blob([bytes], { type: "application/typescript" }), path);
    }
    const r = await mgmt(env, "POST", `/v1/projects/${env.ref}/functions/deploy?slug=${slug}`, form);
    console.log(`  deployed ${slug} (version ${r.version}, verify_jwt ${r.verify_jwt})`);
  }
}

if (import.meta.main) {
  await deployFunctions(await loadEnv());
}
