// The directory's routes (shared/api/directory.yaml). No Cloudflare imports, so the
// tests run it in Deno against SQLite.

import { InvalidIdToken, type Provider } from "./id_token.ts";

/** The part of Cloudflare's D1 API this uses. */
export interface Db {
  prepare(sql: string): Stmt;
  batch(statements: Stmt[]): Promise<unknown[]>;
}
export interface Stmt {
  bind(...values: unknown[]): Stmt;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<unknown>;
}

export interface Verifier {
  verify(idToken: string): Promise<{ provider: Provider; sub: string }>;
}

type Frame = { url: string; key: string };

export const MAX_FRAMES = 20;
export const MAX_TOKENS = 20;
const MAX_BODY = 16 * 1024;
const DAY_S = 86400;
export const TOKEN_MAX_IDLE_S = 400 * DAY_S;

const URL_RE = /^https:\/\/[a-z0-9]{20}\.supabase\.co$/;
const KEY_RE = /^(sb_publishable_[A-Za-z0-9_-]{10,100}|eyJ[A-Za-z0-9_.-]{20,2000})$/;
const TOKEN_RE = /^Bearer (ifd_[A-Za-z0-9_-]{43})$/;

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}
const badRequest = (message: string) => new HttpError(400, "bad_request", message);

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

export async function sha256Hex(text: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, "0")).join("");
}

function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return "ifd_" + btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  if (Number(req.headers.get("Content-Length") ?? 0) > MAX_BODY) throw badRequest("Body too large.");
  const text = await req.text();
  if (text.length > MAX_BODY) throw badRequest("Body too large.");
  try {
    const body = JSON.parse(text);
    if (body && typeof body === "object" && !Array.isArray(body)) return body;
  } catch { /* below */ }
  throw badRequest("Expected a JSON object.");
}

function list<T>(value: unknown, name: string, check: (v: unknown) => v is T): T[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > MAX_FRAMES || !value.every(check)) {
    throw badRequest(`Invalid ${name}.`);
  }
  return value;
}
const isFrame = (v: unknown): v is Frame => {
  const f = v as Frame;
  return !!f && typeof f.url === "string" && typeof f.key === "string" && URL_RE.test(f.url) && KEY_RE.test(f.key);
};
const isUrl = (v: unknown): v is string => typeof v === "string" && URL_RE.test(v);

export function directory(deps: { db: Db; verifier: Verifier; now?: () => number }) {
  const { db, verifier } = deps;
  const nowS = () => Math.floor((deps.now ?? Date.now)() / 1000);

  const framesOf = async (account: string) =>
    (await db.prepare("select url, key from frames where account = ? order by added_at, url").bind(account).all<Frame>())
      .results.map((f) => ({ url: f.url, key: f.key }));

  /** The account behind the request's device token. */
  async function auth(req: Request): Promise<{ account: string; hash: string }> {
    const token = TOKEN_RE.exec(req.headers.get("Authorization") ?? "")?.[1];
    const hash = token ? await sha256Hex(token) : "";
    const row = token
      ? await db.prepare("select account, used_at from tokens where hash = ?").bind(hash).first<{ account: string; used_at: number }>()
      : null;
    if (!row) throw new HttpError(401, "invalid_token", "Missing or unknown device token.");
    const t = nowS();
    if (row.used_at < t - DAY_S) await db.prepare("update tokens set used_at = ? where hash = ?").bind(t, hash).run();
    return { account: row.account, hash };
  }

  async function signIn(req: Request) {
    const idToken = (await readJson(req)).id_token;
    if (typeof idToken !== "string" || !idToken || idToken.length > 8192) throw badRequest("id_token is required.");
    let who;
    try {
      who = await verifier.verify(idToken);
    } catch (e) {
      if (e instanceof InvalidIdToken) throw new HttpError(401, "invalid_id_token", e.message);
      throw e;
    }
    const account = await sha256Hex(`${who.provider}:${who.sub}`);
    const token = newToken();
    const t = nowS();
    await db.batch([
      db.prepare("insert into tokens (hash, account, created_at, used_at) values (?, ?, ?, ?)")
        .bind(await sha256Hex(token), account, t, t),
      db.prepare(`delete from tokens where account = ?1 and hash not in
        (select hash from tokens where account = ?1 order by created_at desc limit ${MAX_TOKENS})`).bind(account),
    ]);
    return json(200, { token, frames: await framesOf(account) });
  }

  async function change(req: Request) {
    const { account } = await auth(req);
    const body = await readJson(req);
    const add = list(body.add, "add", isFrame);
    const remove = list(body.remove, "remove", isUrl);

    const next = new Map((await framesOf(account)).map((f) => [f.url, f.key]));
    for (const url of remove) next.delete(url);
    for (const f of add) next.set(f.url, f.key);
    if (next.size > MAX_FRAMES) throw new HttpError(409, "too_many_frames", `At most ${MAX_FRAMES} frames.`);

    const t = nowS();
    const statements = [
      ...remove.map((url) => db.prepare("delete from frames where account = ? and url = ?").bind(account, url)),
      ...add.map((f) =>
        db.prepare(`insert into frames (account, url, key, added_at) values (?, ?, ?, ?)
          on conflict (account, url) do update set key = excluded.key`).bind(account, f.url, f.key, t)
      ),
    ];
    if (statements.length) await db.batch(statements);
    return json(200, { frames: await framesOf(account) });
  }

  return async function handle(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname.replace(/\/+$/, "");
    try {
      switch (`${req.method} ${path}`) {
        case "POST /v1/sign-in":
          return await signIn(req);
        case "GET /v1/frames":
          return json(200, { frames: await framesOf((await auth(req)).account) });
        case "POST /v1/frames":
          return await change(req);
        case "POST /v1/sign-out": {
          const { hash } = await auth(req);
          await db.prepare("delete from tokens where hash = ?").bind(hash).run();
          return new Response(null, { status: 204 });
        }
        case "DELETE /v1/me": {
          const { account } = await auth(req);
          await db.batch([
            db.prepare("delete from frames where account = ?").bind(account),
            db.prepare("delete from tokens where account = ?").bind(account),
          ]);
          return new Response(null, { status: 204 });
        }
        default:
          throw new HttpError(404, "not_found", "No such route.");
      }
    } catch (e) {
      if (e instanceof HttpError) return json(e.status, { error: { code: e.code, message: e.message } });
      console.error(`${req.method} ${path}: ${e instanceof Error ? e.message : e}`);
      return json(500, { error: { code: "internal", message: "Something went wrong." } });
    }
  };
}

/** Daily: drops device tokens unused for 400 days. */
export async function purgeTokens(db: Db, nowMs = Date.now()) {
  await db.prepare("delete from tokens where used_at < ?").bind(Math.floor(nowMs / 1000) - TOKEN_MAX_IDLE_S).run();
}
