// Runs the app's setup-wizard steps (app/test/live/provision_live_test.dart) against
// the real Management API with the developer's token: a project is created in the
// spare free slot, set up, signed in to as owner, and deleted again.
//   deno run --allow-all tools/dev/provision-live-test.ts
//
// The token goes to `flutter test` through INKFRAME_PROVISION_PAT, never to the terminal.

import { loadEnv } from "./lib.ts";

const { token } = await loadEnv();
const p = new Deno.Command("flutter", {
  cwd: new URL("../../app/", import.meta.url).pathname,
  args: ["test", "test/live/provision_live_test.dart", "--reporter", "expanded", ...Deno.args],
  env: { INKFRAME_PROVISION_PAT: token },
  stdout: "inherit",
  stderr: "inherit",
});
Deno.exit((await p.output()).code);
