// PLAN.md §12.1 scenario with the real frame_sim CLI against the dev project:
// pair → empty sync → upload 3 → sync → delete 1 → reorder → settings → unchanged
// → render → delete frame (410, cache wiped).
//   deno run --allow-all tools/dev/sim-scenario.ts
//
// Sets up the project's frame with a temporary @test.invalid owner, so it needs a
// project without a real owner (like the integration tests). Removes everything it
// created. Compiles frame_sim to a temp dir first.

import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1";
import {
  call,
  cleanup,
  env,
  hasRealFrame,
  makePng,
  newUser,
  purgeLeftovers,
  setupFrame,
  upload,
} from "../../backend/supabase/tests/_lib.ts";

const simDir = new URL("../frame_sim/", import.meta.url).pathname;
const tmp = await Deno.makeTempDir({ prefix: "frame_sim_scenario" });
const exe = `${tmp}/frame_sim`;
const state = `${tmp}/state`;

async function run(cmd: string, args: string[], cwd?: string): Promise<{ code: number; out: string }> {
  const r = await new Deno.Command(cmd, { args, cwd, stdout: "piped", stderr: "piped" }).output();
  const out = new TextDecoder().decode(r.stdout) + new TextDecoder().decode(r.stderr);
  return { code: r.code, out };
}
const sim = async (...args: string[]) => {
  const r = await run(exe, ["--state", state, ...args]);
  console.log(`$ frame_sim ${args.join(" ")}\n${r.out.trimEnd().replace(/^/gm, "  ")}`);
  return r;
};
const manifestIds = async () =>
  (await Deno.readTextFile(`${state}/cache/manifest.txt`)).split("\n").filter(Boolean).map((l) => l.split(" ")[0]);

const step = (s: string) => console.log(`\n── ${s}`);

try {
  step("compile frame_sim");
  const c = await run("dart", ["compile", "exe", "bin/frame_sim.dart", "-o", exe], simDir);
  assertEquals(c.code, 0, c.out);

  await purgeLeftovers();
  if (await hasRealFrame()) throw new Error("This project has a real frame owner; use a throwaway project.");
  const M = await newUser("sim");
  await setupFrame(M, "Sim tester", "Sim frame");

  step("1. connect");
  const t = await call("POST", "/app-api/pairing-tokens", { token: M.token });
  assertEquals(t.status, 201);
  const claim = await sim("claim", "--ref", env.ref, "--token", t.body.pairing_token);
  assertEquals(claim.code, 0);
  const empty = await sim("sync");
  assertMatch(empty.out, /: 0 images/);
  assertMatch(empty.out, /TZ CET-1CEST/);

  step("2. upload 3 → sync downloads 3");
  const ids: string[] = [];
  for (let i = 0; i < 3; i++) {
    const r = await upload(M, await makePng(800, 480, 100 + i));
    assertEquals(r.status, 200, JSON.stringify(r.body));
    ids.push(r.body.id);
  }
  const s3 = await sim("sync");
  assertMatch(s3.out, /3 images \(\+3 -0\)/);
  assertEquals(await manifestIds(), ids);

  step("3. delete 1 → sync mirrors");
  await call("POST", "/app-api/images/delete", { token: M.token, body: { image_ids: [ids[0]] } });
  const s2 = await sim("sync");
  assertMatch(s2.out, /2 images \(\+0 -1\)/);
  assertEquals(await manifestIds(), [ids[1], ids[2]]);

  step("4. reorder → positions change");
  await call("POST", "/app-api/images/reorder", { token: M.token, body: { image_id: ids[2], after_image_id: null } });
  await sim("sync");
  assertEquals(await manifestIds(), [ids[2], ids[1]]);

  step("5. settings change → reflected");
  await call("PATCH", "/app-api/frame/settings", {
    token: M.token, body: { display_order: "sequential", quiet_start: "22:00", quiet_end: "07:00" },
  });
  const s5 = await sim("sync");
  assertMatch(s5.out, /sequential/);
  assertMatch(s5.out, /quiet 22:00–07:00/);

  step("6. unchanged manifest → images omitted");
  assertMatch((await sim("sync")).out, /unchanged; 2 images cached/);

  step("render + status");
  const r = await sim("render", "--out", `${tmp}/current.png`);
  assertEquals(r.code, 0);
  const png = await Deno.readFile(`${tmp}/current.png`);
  assertEquals([...png.subarray(1, 4)], [0x50, 0x4e, 0x47]);
  await sim("status");

  step("7. disconnect the frame → 410, cache wiped");
  assertEquals((await call("POST", "/app-api/frame/disconnect", { token: M.token })).status, 204);
  const gone = await sim("sync");
  assertEquals(gone.code, 1);
  assertMatch(gone.out, /Not connected to an album/);
  const left = [...Deno.readDirSync(`${state}/cache`)].filter((e) => e.name.endsWith(".png"));
  assertEquals(left.length, 0);
  assertMatch((await sim("status")).out, /paired\s+no/);

  console.log("\n§12.1 scenario with frame_sim: PASSED");
} finally {
  await cleanup();
  await Deno.remove(tmp, { recursive: true });
}
assert(true);
