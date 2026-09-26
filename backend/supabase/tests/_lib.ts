// Helpers for the integration tests. They run against the dev project through the
// real APIs (PostgREST, Storage, Edge Functions) with real user sessions, so they
// cover grants, RLS, storage policies and the functions together.
//
// Keys are fetched from the Management API at start-up and never written to disk.
// Test users are email/password users on the dev project only (@test.invalid);
// family projects have email sign-in turned off.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.117.1";
import { loadEnv, sql } from "../../../tools/dev/lib.ts";

export { sql };
export const env = await loadEnv();
export const PROJECT_URL = `https://${env.ref}.supabase.co`;
export const FN = `${PROJECT_URL}/functions/v1`;

const keys: { type: string; api_key: string }[] = await (await fetch(
  `https://api.supabase.com/v1/projects/${env.ref}/api-keys?reveal=true`,
  { headers: { Authorization: `Bearer ${env.token}` } },
)).json();
const key = (type: string) => keys.find((k) => k.type === type)?.api_key ?? "";
export const PUBLIC_KEY = key("publishable");
const SECRET_KEY = key("secret");

// Every request fails after this long, so a stalled call fails the step instead of
// hanging the run.
export const TIMEOUT_MS = 30_000;
const timedFetch: typeof fetch = (input, init) =>
  fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(TIMEOUT_MS) });

const noSession = {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: timedFetch },
};
export const admin = createClient(PROJECT_URL, SECRET_KEY, noSession);
export const anon = createClient(PROJECT_URL, PUBLIC_KEY, noSession);

export type User = { id: string; email: string; token: string; db: SupabaseClient };

const RUN = crypto.randomUUID().slice(0, 8);
export const created = { users: [] as string[], frame: false };

export async function newUser(label: string): Promise<User> {
  const email = `${label}-${RUN}@test.invalid`;
  const password = crypto.randomUUID();
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  created.users.push(data.user.id);
  const db = createClient(PROJECT_URL, PUBLIC_KEY, noSession);
  const s = await db.auth.signInWithPassword({ email, password });
  if (s.error) throw s.error;
  return { id: data.user.id, email, token: s.data.session.access_token, db };
}

const q = (s: string) => `'${s.replaceAll("'", "''")}'`;

// The setup wizard describes the frame and adds its owner with SQL; tests do the same.
export async function setupFrame(owner: User, ownerName: string, frameName = "Test frame",
  modelId = "reterminal-e1002", timezone = "Europe/Berlin"): Promise<string> {
  const [{ id }] = await sql<{ id: string }>(env,
    `select private.setup_frame(${q(frameName)}, ${q(modelId)}, ${q(timezone)}) as id`);
  created.frame = true;
  await sql(env, `select private.set_owner('${owner.id}', ${q(ownerName)})`);
  return id;
}

// A member without going through an invite (invites are tested separately).
export async function addMember(u: User, name: string) {
  await sql(env, `insert into public.members (user_id, role, display_name) values ('${u.id}', 'member', ${q(name)})`);
}

export type Res = { status: number; body: any }; // deliberately loose for assertions

export async function call(
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
): Promise<Res> {
  const headers: Record<string, string> = { ...opts.headers };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(`${FN}${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, "0")).join("");
}

// ── A small indexed PNG, like the app will produce (4-bit, 6-colour palette) ──

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(b: Uint8Array): number {
  let c = 0xffffffff;
  for (const x of b) c = CRC_TABLE[(c ^ x) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length);
  const v = new DataView(out.buffer);
  v.setUint32(0, data.length);
  out.set(new TextEncoder().encode(type), 4);
  out.set(data, 8);
  v.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}
async function zlib(data: Uint8Array<ArrayBuffer>): Promise<Uint8Array> {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

// Different seeds give different pixels, so different sha256s.
export async function makePng(w: number, h: number, seed: number): Promise<Uint8Array<ArrayBuffer>> {
  const ihdr = new Uint8Array(13);
  const v = new DataView(ihdr.buffer);
  v.setUint32(0, w);
  v.setUint32(4, h);
  ihdr.set([4, 3, 0, 0, 0], 8); // bit depth 4, colour type 3 (indexed)
  const plte = new Uint8Array([0, 0, 0, 255, 255, 255, 255, 255, 0, 255, 0, 0, 0, 0, 255, 0, 255, 0]);
  const rowLen = 1 + Math.ceil(w / 2);
  const raw = new Uint8Array(rowLen * h);
  // The pattern repeats every 6 seeds, so the first 12 pixels spell the seed in base 6.
  const px = (x: number, y: number) =>
    y === 0 && x < 12 ? Math.floor(seed / 6 ** x) % 6 : (x + y + seed) % 6;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x += 2) {
      raw[y * rowLen + 1 + x / 2] = (px(x, y) << 4) | px(x + 1, y);
    }
  }
  const parts = [
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("PLTE", plte),
    chunk("IDAT", await zlib(raw)),
    chunk("IEND", new Uint8Array()),
  ];
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

// request-upload → PUT → finalize. Returns the finalize response.
export async function upload(u: User, png: Uint8Array<ArrayBuffer>, w = 800, h = 480): Promise<Res> {
  const req = await call("POST", "/app-api/images/request-upload", {
    token: u.token,
    body: { sha256: await sha256Hex(png), bytes: png.length, width: w, height: h },
  });
  if (req.status !== 200) return req;
  const put = await timedFetch(req.body.upload_url, { method: "PUT", headers: { "Content-Type": "image/png" }, body: png });
  if (!put.ok) throw new Error(`upload PUT failed ${put.status}: ${await put.text()}`);
  await put.body?.cancel();
  return call("POST", "/app-api/images/finalize", { token: u.token, body: { image_id: req.body.image_id } });
}

export { timedFetch as fetch };

// Deletes the frame, its images (objects first) and invites. Members go with their
// auth users.
async function removeFrame() {
  const rows = await sql<{ storage_path: string }>(env, "select storage_path from public.images");
  if (rows.length) await admin.storage.from("frame-images").remove(rows.map((r) => r.storage_path));
  await sql(env, "delete from public.images where true; delete from public.frame where true;");
}

// Removes everything the run created: storage objects, the frame, auth users (which
// cascades memberships, tokens and invites).
export async function cleanup() {
  if (created.frame) await removeFrame();
  for (const id of created.users) await admin.auth.admin.deleteUser(id);
}

// Whether the project already has a frame that isn't the tests' own (a real owner).
export async function hasRealFrame(): Promise<boolean> {
  const [{ n }] = await sql<{ n: number }>(env, `
    select count(*)::int as n from public.members m join auth.users u on u.id = m.user_id
    where m.role = 'owner' and u.email not like '%@test.invalid'`);
  return n > 0;
}

// Removes what an interrupted run left behind: a frame owned by a test user (or by
// nobody), and every @test.invalid user. Returns how many users it found.
export async function purgeLeftovers(): Promise<number> {
  if (!(await hasRealFrame())) await removeFrame();
  const users = await sql<{ id: string }>(env, `select id from auth.users where email like '%@test.invalid'`);
  for (const u of users) await admin.auth.admin.deleteUser(u.id);
  return users.length;
}
