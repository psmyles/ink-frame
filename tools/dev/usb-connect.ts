// Connects the real frame over USB (Phase 4a: firmware/tools/console.py) to a test album
// on a throwaway project, and adds or removes its photos, so the firmware can be tried
// end to end before Bluetooth (4b).
//
//   SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts setup --ssid <wifi> [--photos 3] [--erase-sd]
//   SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts photos --add 5
//   SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts photos --clear
//   SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts remove
//
// setup makes a test owner and album (the project must have no real owner), uploads test
// photos, makes a pairing token and runs the console's provision, which asks for the
// Wi-Fi password itself (or reads WIFI_PASSWORD): it never passes through here. The test
// owner's sign-in is kept in firmware/.env.usb-frame (gitignored) for the other commands.

import { parseArgs } from "jsr:@std/cli@1/parse-args";
import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import {
  call,
  FN,
  hasRealFrame,
  makePng,
  newUser,
  PROJECT_URL,
  PUBLIC_KEY,
  purgeLeftovers,
  setupFrame,
  sql,
  env,
  upload,
} from "../../backend/supabase/tests/_lib.ts";

const args = parseArgs(Deno.args, {
  string: ["ssid", "photos", "add", "port"],
  boolean: ["erase-sd", "clear"],
});
const cmd = args._[0];
const stateFile = new URL("../../firmware/.env.usb-frame", import.meta.url);
const pio = new URL("../../firmware/tools/console.py", import.meta.url).pathname;

type Saved = { ref: string; email: string; password: string };

async function saved(): Promise<Saved> {
  const s = JSON.parse(await Deno.readTextFile(stateFile)) as Saved;
  if (s.ref !== env.ref) throw new Error(`firmware/.env.usb-frame is for ${s.ref}, not ${env.ref}`);
  return s;
}

async function ownerToken(s: Saved): Promise<string> {
  const c = createClient(PROJECT_URL, PUBLIC_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await c.auth.signInWithPassword({ email: s.email, password: s.password });
  if (error) throw error;
  return data.session!.access_token;
}

async function addPhotos(token: string, n: number) {
  const [{ max }] = await sql<{ max: number }>(env, "select coalesce(count(*), 0)::int as max from public.images");
  for (let i = 0; i < n; i++) {
    const r = await upload({ token } as never, await makePng(800, 480, max + i + Date.now() % 1000));
    if (r.status !== 200) throw new Error(`upload: ${r.status} ${JSON.stringify(r.body)}`);
  }
  console.log(`${n} photos added`);
}

async function pythonForPio(): Promise<string> {
  const out = await new Deno.Command("pio", { args: ["system", "info", "--json-output"], stdout: "piped" }).output();
  return JSON.parse(new TextDecoder().decode(out.stdout)).python_exe.value as string;
}

if (cmd === "setup") {
  if (!args.ssid) throw new Error("--ssid is required");
  await purgeLeftovers();
  if (await hasRealFrame()) throw new Error("This project has a real frame owner; use a throwaway project.");
  const owner = await newUser("usb-owner");
  await setupFrame(owner, "Tester", "Test album", "reterminal-e1002", "Asia/Kolkata");
  await Deno.writeTextFile(stateFile, JSON.stringify({ ref: env.ref, email: owner.email, password: owner.password }), {
    mode: 0o600,
  });
  await addPhotos(owner.token, Number(args.photos ?? 3));
  const t = await call("POST", "/app-api/pairing-tokens", { token: owner.token });
  if (t.status !== 201) throw new Error(`pairing token: ${t.status} ${JSON.stringify(t.body)}`);
  const py = await pythonForPio();
  const p = new Deno.Command(py, {
    args: [
      pio,
      ...(args.port ? ["--port", args.port] : []),
      "provision",
      "--ssid",
      args.ssid,
      "--api-base-url",
      FN,
      "--pairing-token",
      t.body.pairing_token,
      ...(args["erase-sd"] ? ["--erase-sd"] : []),
    ],
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  Deno.exit((await p.output()).code);
} else if (cmd === "photos") {
  const token = await ownerToken(await saved());
  if (args.clear) {
    const rows = await sql<{ id: string }>(env, "select id from public.images");
    if (rows.length) {
      const r = await call("POST", "/app-api/images/delete", { token, body: { image_ids: rows.map((x) => x.id) } });
      if (r.status >= 300) throw new Error(`delete: ${r.status} ${JSON.stringify(r.body)}`);
    }
    console.log(`${rows.length} photos removed`);
  }
  if (args.add) await addPhotos(token, Number(args.add));
} else if (cmd === "remove") {
  await purgeLeftovers();
  await Deno.remove(stateFile).catch(() => {});
  console.log("test album and owner removed");
} else {
  console.log("usage: usb-connect.ts setup --ssid <wifi> [--photos N] [--erase-sd] | photos --add N | photos --clear | remove");
}
