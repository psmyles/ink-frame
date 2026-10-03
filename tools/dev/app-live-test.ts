// Runs the app's live tests (app/test/live/) against the dev project: sets up a frame
// with a temporary @test.invalid owner, creates an invite, hands both to
// `flutter test` through INKFRAME_LIVE, then removes everything.
//   deno run --allow-all tools/dev/app-live-test.ts
//
// Needs a project without a real owner (like the backend tests).

import {
  call,
  cleanup,
  env,
  hasRealFrame,
  newUser,
  PROJECT_URL,
  PUBLIC_KEY,
  purgeLeftovers,
  setupFrame,
} from "../../backend/supabase/tests/_lib.ts";

const appDir = new URL("../../app/", import.meta.url).pathname;

await purgeLeftovers();
if (await hasRealFrame()) throw new Error("This project has a real frame owner; use a throwaway project.");

let code = 1;
try {
  const owner = await newUser("app-owner");
  await setupFrame(owner, "Priya", "Kitchen");
  const inv = await call("POST", "/app-api/invites", { token: owner.token, body: { max_uses: 2 } });
  if (inv.status !== 201) throw new Error(`invite: ${inv.status} ${JSON.stringify(inv.body)}`);

  const run = crypto.randomUUID().slice(0, 8);
  const fixture = {
    url: PROJECT_URL,
    key: PUBLIC_KEY,
    code: inv.body.code,
    owner_email: owner.email,
    owner_password: owner.password,
    member_email: `app-member-${run}@test.invalid`,
    outsider_email: `app-outsider-${run}@test.invalid`,
    password: crypto.randomUUID(),
  };
  const p = new Deno.Command("flutter", {
    // One file at a time: they share the frame (one renames it briefly).
    args: ["test", "test/live", "--concurrency=1", ...Deno.args],
    cwd: appDir,
    env: { INKFRAME_LIVE: JSON.stringify(fixture) },
    stdout: "inherit",
    stderr: "inherit",
  }).spawn();
  code = (await p.status).code;
} finally {
  await cleanup();
  // Users the app signed up itself.
  await purgeLeftovers();
  console.log(`dev project ${env.ref} cleaned up`);
}
Deno.exit(code);
