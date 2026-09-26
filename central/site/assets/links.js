// Link handling for the /join and /oauth pages. Pure functions, tested by
// central/tests/links_test.ts; the app has its own parser for the same formats.
//
// /join#u=<project_url>&k=<publishable_key>[&c=<invite_code>]
//   An invite (with c) or "Use on another device" (u/k repeated once per frame, no c).
//   The fragment never reaches the server; the page hands it to inkframe://join?...
// /oauth?code=...&state=...  (or error=...&error_description=...)
//   The Supabase OAuth callback on mobile; forwarded to inkframe://supabase-oauth?...

const PROJECT_URL = /^https:\/\/[a-z0-9]{20}\.supabase\.co$/;
const KEY = /^(sb_publishable_[A-Za-z0-9_-]{10,100}|eyJ[A-Za-z0-9_.-]{20,2000})$/;
const CODE = /^[A-Za-z0-9-]{6,64}$/;
const MAX_FRAMES = 20;

/** Returns {frames: [{url, key}], code: string|null, appUrl} or null if the link is broken. */
export function parseJoin(fragment) {
  const raw = fragment.replace(/^#/, "");
  const p = new URLSearchParams(raw);
  const urls = p.getAll("u");
  const keys = p.getAll("k");
  const codes = p.getAll("c");
  if (urls.length === 0 || urls.length !== keys.length || urls.length > MAX_FRAMES) return null;
  if (codes.length > 1 || (codes.length === 1 && urls.length !== 1)) return null;
  const frames = urls.map((url, i) => ({ url: url.replace(/\/$/, ""), key: keys[i] }));
  if (!frames.every((f) => PROJECT_URL.test(f.url) && KEY.test(f.key))) return null;
  const code = codes[0] ?? null;
  if (code !== null && !CODE.test(code)) return null;

  const out = new URLSearchParams();
  for (const f of frames) {
    out.append("u", f.url);
    out.append("k", f.key);
  }
  if (code) out.append("c", code);
  return { frames, code, appUrl: `inkframe://join?${out}` };
}

const OAUTH_PARAMS = ["code", "state", "error", "error_description"];

/** Returns the inkframe:// URL for a Supabase OAuth callback, or null if it isn't one. */
export function oauthTarget(search) {
  const p = new URLSearchParams(search.replace(/^\?/, ""));
  const out = new URLSearchParams();
  for (const name of OAUTH_PARAMS) {
    const v = p.get(name);
    if (v !== null && v.length <= 2048) out.set(name, v);
  }
  const ok = (out.has("code") && out.has("state")) || out.has("error");
  return ok ? `inkframe://supabase-oauth?${out}` : null;
}

/** "ios" | "android" | "desktop", for choosing what the page offers. */
export function platformOf(userAgent) {
  if (/iPhone|iPad|iPod/.test(userAgent)) return "ios";
  if (/Android/.test(userAgent)) return "android";
  return "desktop";
}
