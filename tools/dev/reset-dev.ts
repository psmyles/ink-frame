// Drops everything the migrations created in the dev project, then re-applies them.
// For iterating on unreleased migrations only.
//   deno run --allow-read --allow-net --allow-env tools/dev/reset-dev.ts --yes
//
// Only runs against the project in backend/.env.local, and refuses if the bucket
// holds any objects (they can only be deleted through the Storage API; remove them
// first). Auth users are left alone.

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { loadEnv, sql } from "./lib.ts";
import { applyMigrations } from "./migrate.ts";

const args = parseArgs(Deno.args, { boolean: ["yes"] });
const env = await loadEnv();
if (!args.yes) {
  console.log(`Resets project ${env.ref}: drops all tables and functions in public, the private schema and the cron jobs, then re-runs the migrations. Pass --yes.`);
  Deno.exit(1);
}

const [{ n }] = await sql<{ n: number }>(env,
  "select count(*)::int as n from storage.objects where bucket_id = 'frame-images'");
if (n > 0) throw new Error(`frame-images holds ${n} objects; delete them through the Storage API first.`);

await sql(env, `
begin;
select cron.unschedule(jobname) from cron.job where jobname like 'inkframe-%';
drop policy if exists "frame members read frame images" on storage.objects;
drop policy if exists "members read frame images" on storage.objects;
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('drop table if exists public.%I cascade', r.tablename);
  end loop;
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname like 'svc\\_%' loop
    execute format('drop function if exists %s cascade', r.f);
  end loop;
end $$;
drop schema if exists private cascade;
commit;`);
console.log(`reset ${env.ref}`);
await applyMigrations(env);
