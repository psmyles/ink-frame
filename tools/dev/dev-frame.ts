// A frame on the dev project to try the app with, until the setup wizard exists
// (Phase 3e). Creates the frame with a placeholder owner and prints an invite link;
// join it in the app in developer mode with any email and password.
//   deno run --allow-read --allow-net --allow-env tools/dev/dev-frame.ts [--name Kitchen] [--uses 5]
//   deno run --allow-read --allow-net --allow-env tools/dev/dev-frame.ts --invite     (another link)
//   deno run --allow-read --allow-net --allow-env tools/dev/dev-frame.ts --remove     (so the tests can run)
//   deno run --allow-read --allow-write --allow-net --allow-env tools/dev/dev-frame.ts --owner-login
//     (sign in as the owner in the app's developer mode: the password goes into
//      backend/.env.local as DEV_OWNER_PASSWORD, never to the terminal)
//
// The owner (dev-owner@inkframe.invalid) isn't a test user, so the integration tests
// skip while this frame exists instead of deleting it.

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { admin, call, PROJECT_URL, PUBLIC_KEY, sql, env } from "../../backend/supabase/tests/_lib.ts";

const args = parseArgs(Deno.args, {
  string: ["name", "uses"],
  boolean: ["invite", "remove", "owner-login"],
  default: { name: "Dev frame", uses: "5" },
});
const EMAIL = "dev-owner@inkframe.invalid";
const PAGES = "https://psmyles.github.io/ink-frame";
const q = (s: string) => `'${s.replaceAll("'", "''")}'`;

async function ownerSession(password: string) {
  const res = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: PUBLIC_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: EMAIL, password }),
  });
  if (!res.ok) throw new Error(`owner sign-in: ${res.status}`);
  return (await res.json()).access_token as string;
}

const ENV_FILE = new URL("../../backend/.env.local", import.meta.url);

// DEV_OWNER_PASSWORD from backend/.env.local, if --owner-login set one.
async function savedOwnerPassword(): Promise<string | undefined> {
  const text = await Deno.readTextFile(ENV_FILE);
  return /^DEV_OWNER_PASSWORD=(.+)$/m.exec(text)?.[1].trim();
}

async function saveOwnerPassword(password: string) {
  const lines = (await Deno.readTextFile(ENV_FILE)).split("\n").filter((l) => !l.startsWith("DEV_OWNER_PASSWORD="));
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  await Deno.writeTextFile(ENV_FILE, [...lines, `DEV_OWNER_PASSWORD=${password}`, ""].join("\n"));
}

// The owner's password: the saved one after --owner-login, else a fresh random one
// each run (nobody needs to know it).
async function owner(): Promise<{ id: string; token: string }> {
  const password = (await savedOwnerPassword()) ?? crypto.randomUUID();
  const [row] = await sql<{ id: string }>(env, `select id from auth.users where email = ${q(EMAIL)}`);
  let id = row?.id;
  if (id) {
    const { error } = await admin.auth.admin.updateUserById(id, { password });
    if (error) throw error;
  } else {
    const { data, error } = await admin.auth.admin.createUser({ email: EMAIL, password, email_confirm: true });
    if (error) throw error;
    id = data.user.id;
  }
  return { id, token: await ownerSession(password) };
}

if (args.remove) {
  const rows = await sql<{ storage_path: string }>(env, "select storage_path from public.images");
  if (rows.length) await admin.storage.from("frame-images").remove(rows.map((r) => r.storage_path));
  await sql(env, "delete from public.images where true; delete from public.frame where true;");
  const users = await sql<{ id: string }>(env, "select user_id as id from public.members");
  for (const u of users) await admin.auth.admin.deleteUser(u.id);
  const [o] = await sql<{ id: string }>(env, `select id from auth.users where email = ${q(EMAIL)}`);
  if (o) await admin.auth.admin.deleteUser(o.id);
  console.log(`Removed the dev frame and its ${users.length} people.`);
  Deno.exit(0);
}

if (args["owner-login"]) {
  if (!(await savedOwnerPassword())) await saveOwnerPassword(crypto.randomUUID());
  await owner();
  console.log(`Owner sign-in for the app's developer mode:\n  email:    ${EMAIL}\n  password: DEV_OWNER_PASSWORD in backend/.env.local`);
  Deno.exit(0);
}

const [{ n }] = await sql<{ n: number }>(env, "select count(*)::int as n from public.frame");
const o = await owner();
if (n === 0) {
  if (args.invite) throw new Error("No dev frame yet; run without --invite first.");
  await sql(env, `select private.setup_frame(${q(args.name)}, 'reterminal-e1002', 'Europe/Berlin')`);
  await sql(env, `select private.set_owner('${o.id}', 'Dev owner')`);
  console.log(`Created "${args.name}" on ${env.ref}.`);
} else if (!args.invite) {
  console.log("The dev project already has a frame; making a new invite for it.");
}

const inv = await call("POST", "/app-api/invites", {
  token: o.token,
  body: { max_uses: Number(args.uses), expires_in_s: 7 * 86400 },
});
if (inv.status !== 201) throw new Error(`invite: ${inv.status} ${JSON.stringify(inv.body)}`);
const link = `${PAGES}/join#u=${encodeURIComponent(PROJECT_URL)}&k=${PUBLIC_KEY}&c=${inv.body.code}`;
console.log(`\nInvite (${args.uses} uses, 7 days):\n${link}\n`);
