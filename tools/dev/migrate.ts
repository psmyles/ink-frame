// Applies backend/supabase migrations to a project through the Management API, the
// same way the app's setup wizard will (PLAN.md §6.2 step 3, §6.3).
//   deno run --allow-read --allow-net --allow-env tools/dev/migrate.ts [--status]
//
// Reads SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF from the environment or
// backend/.env.local. Each pending migration runs in one transaction together with
// its schema_version row, so a failure leaves the database at the previous version.
// Then seed.sql is applied and private.config.project_url is written.

import { type Env, loadEnv, sql } from "./lib.ts";

const root = new URL("../../", import.meta.url);

export async function applyMigrations(env: Env, opts: { statusOnly?: boolean } = {}): Promise<void> {
  const migrationsDir = new URL("backend/supabase/migrations/", root);
  const migrations: { version: number; name: string; file: URL }[] = [];
  for await (const e of Deno.readDir(migrationsDir)) {
    const m = e.isFile && /^(\d+)_.+\.sql$/.exec(e.name);
    if (m) migrations.push({ version: Number(m[1]), name: e.name, file: new URL(e.name, migrationsDir) });
  }
  migrations.sort((a, b) => a.version - b.version);

  // Two queries: Postgres resolves table names before evaluating any CASE.
  const [{ exists }] = await sql<{ exists: boolean }>(env,
    `select to_regclass('public.schema_version') is not null as exists`);
  const current = exists
    ? (await sql<{ v: number }>(env, `select coalesce(max(version), 0) as v from public.schema_version`))[0].v
    : 0;
  const pending = migrations.filter((m) => m.version > current);

  console.log(`project ${env.ref}: schema_version ${current}; ${pending.length} pending`);
  for (const m of pending) console.log(`  pending ${m.name}`);
  if (opts.statusOnly) return;

  for (const m of pending) {
    const body = await Deno.readTextFile(m.file);
    await sql(env, `begin;\n${body}\n;insert into public.schema_version (version) values (${m.version});\ncommit;`);
    console.log(`  applied ${m.name}`);
  }

  await sql(env, await Deno.readTextFile(new URL("backend/supabase/seed.sql", root)));
  console.log("  applied seed.sql");

  await sql(env, `insert into private.config (key, value) values ('project_url', 'https://${env.ref}.supabase.co')
    on conflict (key) do update set value = excluded.value`);
  console.log("  set private.config.project_url");
}

if (import.meta.main) {
  await applyMigrations(await loadEnv(), { statusOnly: Deno.args.includes("--status") });
}
