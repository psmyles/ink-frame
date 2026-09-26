// app-api: every write the app makes (PLAN.md §7.4, shared/api/openapi.yaml).
// One project = one frame. Auth: the user's Supabase JWT, verified here (verify_jwt
// is off, config.toml). Membership and permissions are checked by the svc_* SQL
// functions.

import { Hono } from "npm:hono@4.13.8";
import { z } from "npm:zod@4.6.5";
import { normalizeCode, randomCode, sha256Hex } from "../_shared/crypto.ts";
import { admin, BUCKET, removeObjects, rpc } from "../_shared/db.ts";
import { ApiError, bearer, body, check, errorResponse, fail } from "../_shared/http.ts";
import {
  DisplayName,
  DisplayOrder,
  FrameName,
  LocalTime,
  MAX_IMAGE_BYTES,
  ModelId,
  Sha256,
  Timezone,
  Uuid,
} from "../_shared/schemas.ts";
import { TZ_POSIX } from "../_shared/tz.ts";

// Supabase free-tier storage (PLAN.md §14: verify).
const FREE_TIER_BYTES = 1024 ** 3;
// Supabase signed upload URLs last 2 hours.
const UPLOAD_URL_TTL_MS = 2 * 60 * 60 * 1000;

type Env = { Variables: { user: string } };
const app = new Hono<Env>().basePath("/app-api");
app.onError((err, c) => errorResponse(c, err));
app.notFound((c) => errorResponse(c, new ApiError(404, "not_found", "No such endpoint.")));

// ── Maintenance (secret header, no user) ──────────────────────────────────────

app.post("/internal/maintenance", async (c) => {
  const secret = c.req.header("x-maintenance-secret");
  if (!secret || !(await rpc<boolean>("svc_check_maintenance_secret", { p_secret: secret }))) {
    fail("unauthenticated", "Missing or wrong maintenance secret.");
  }
  let deleted = 0;
  for (;;) {
    const names = await rpc<string[]>("svc_orphan_objects", { p_limit: 500 });
    if (!names.length) break;
    const { error } = await admin.storage.from(BUCKET).remove(names);
    if (error) throw error;
    deleted += names.length;
    if (names.length < 500) break;
  }
  return c.json({ deleted_objects: deleted });
});

// ── Everything else: signed-in users ──────────────────────────────────────────

app.use("*", async (c, next) => {
  const token = bearer(c) ?? fail("unauthenticated", "Missing access token.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) fail("unauthenticated", "Invalid or expired access token.");
  c.set("user", data.user.id);
  await next();
});

const param = (c: { req: { param: (k: string) => string } }, k: string) => check(Uuid, c.req.param(k));

// ── Frame (owner) ─────────────────────────────────────────────────────────────

app.patch("/frame", async (c) => {
  const b = await body(c, z.strictObject({
    name: FrameName.optional(),
    model_id: ModelId.optional(),
    clear_photos: z.boolean().optional(),
  }).refine((o) => o.name !== undefined || o.model_id !== undefined, "Send a name or a model_id."));
  const r = await rpc<{ frame: Record<string, unknown>; storage_paths: string[] }>("svc_update_frame", {
    p_user: c.get("user"),
    p_patch: b,
  });
  await removeObjects(r.storage_paths);
  return c.json(r.frame);
});

const SettingsPatch = z.strictObject({
  image_interval_s: z.int().min(3600).max(172800),
  display_order: DisplayOrder,
  sync_interval_s: z.int().min(3600).max(172800),
  quiet_start: LocalTime.nullable(),
  quiet_end: LocalTime.nullable(),
  timezone: Timezone,
}).partial().refine((o) => Object.keys(o).length > 0, "Send at least one setting.");

app.patch("/frame/settings", async (c) => {
  const patch = await body(c, SettingsPatch);
  if (patch.timezone !== undefined && !TZ_POSIX[patch.timezone]) {
    fail("unknown_timezone", `Unknown timezone ${patch.timezone}.`);
  }
  return c.json(await rpc("svc_update_frame_settings", { p_user: c.get("user"), p_patch: patch }));
});

app.post("/pairing-tokens", async (c) => {
  const token = randomCode(26);
  const expiresAt = await rpc<string>("svc_create_pairing_token", {
    p_user: c.get("user"),
    p_token_hash: await sha256Hex(token),
  });
  return c.json({ pairing_token: token, expires_at: expiresAt }, 201);
});

app.post("/frame/disconnect", async (c) => {
  await rpc("svc_disconnect_frame", { p_user: c.get("user") });
  return c.body(null, 204);
});

// ── Images ────────────────────────────────────────────────────────────────────

app.post("/images/request-upload", async (c) => {
  const b = await body(c, z.strictObject({
    sha256: Sha256,
    bytes: z.int().min(1),
    width: z.int().min(1).max(4096),
    height: z.int().min(1).max(4096),
  }));
  if (b.bytes > MAX_IMAGE_BYTES) fail("too_large", `Images are limited to ${MAX_IMAGE_BYTES} bytes.`);

  const r = await rpc<{ image_id: string; storage_path: string }>("svc_request_upload", {
    p_user: c.get("user"),
    p_sha256: b.sha256,
    p_bytes: b.bytes,
    p_width: b.width,
    p_height: b.height,
  });
  const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(r.storage_path, { upsert: true });
  if (error) throw error;
  return c.json({
    image_id: r.image_id,
    upload_url: data.signedUrl,
    expires_at: new Date(Date.now() + UPLOAD_URL_TTL_MS).toISOString(),
  });
});

type ImageRow = {
  id: string;
  storage_path: string;
  status: "pending" | "ready";
  bytes: number;
  width: number;
  height: number;
};

// Checks the PNG signature and IHDR width/height.
function pngProblem(png: Uint8Array, width: number, height: number): string | null {
  const SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (png.length < 24 || SIG.some((b, i) => png[i] !== b)) return "Not a PNG file.";
  if (new TextDecoder().decode(png.subarray(12, 16)) !== "IHDR") return "PNG has no IHDR chunk first.";
  const v = new DataView(png.buffer, png.byteOffset, png.byteLength);
  const w = v.getUint32(16), h = v.getUint32(20);
  if (w !== width || h !== height) return `PNG is ${w}x${h}; expected ${width}x${height}.`;
  return null;
}

app.post("/images/finalize", async (c) => {
  const user = c.get("user");
  const { image_id } = await body(c, z.strictObject({ image_id: Uuid }));
  const img = await rpc<ImageRow>("svc_get_upload", { p_user: user, p_image: image_id });

  if (img.status === "pending") {
    const { data, error } = await admin.storage.from(BUCKET).download(img.storage_path);
    if (error || !data) fail("not_uploaded", "Nothing has been uploaded for this image yet.");
    const png = new Uint8Array(await data.arrayBuffer());

    let problem: [string, string] | null = null;
    if (png.length !== img.bytes) {
      problem = ["size_mismatch", `Uploaded ${png.length} bytes; expected ${img.bytes}.`];
    } else {
      const p = pngProblem(png, img.width, img.height);
      if (p) problem = ["invalid_png", p];
    }
    if (problem) {
      await removeObjects([img.storage_path]);
      await rpc("svc_discard_upload", { p_user: user, p_image: image_id });
      fail(problem[0], problem[1]);
    }
  }
  return c.json(await rpc("svc_mark_ready", { p_user: user, p_image: image_id }));
});

app.post("/images/delete", async (c) => {
  const b = await body(c, z.strictObject({ image_ids: z.array(Uuid).min(1).max(100) }));
  const r = await rpc<{ deleted_ids: string[]; storage_paths: string[] }>("svc_delete_images", {
    p_user: c.get("user"),
    p_ids: [...new Set(b.image_ids)],
  });
  await removeObjects(r.storage_paths);
  return c.json({ deleted_ids: r.deleted_ids });
});

app.post("/images/reorder", async (c) => {
  const b = await body(c, z.strictObject({ image_id: Uuid, after_image_id: Uuid.nullable() }));
  return c.json(await rpc("svc_reorder_image", {
    p_user: c.get("user"),
    p_image: b.image_id,
    p_after: b.after_image_id,
  }));
});

// ── People ────────────────────────────────────────────────────────────────────

app.post("/invites/accept", async (c) => {
  const b = await body(c, z.strictObject({
    code: z.string().min(10).max(16),
    display_name: DisplayName.optional(),
  }));
  const code = normalizeCode(b.code);
  if (!/^[0-9A-HJKMNP-TV-Z]{10}$/.test(code)) fail("invalid_invite", "This invite code is not valid.");
  return c.json(await rpc("svc_accept_invite", {
    p_user: c.get("user"),
    p_code_hash: await sha256Hex(code),
    p_display_name: b.display_name ?? null,
  }));
});

app.post("/invites", async (c) => {
  const b = await body(c, z.strictObject({
    max_uses: z.int().min(1).max(50).default(1),
    expires_in_s: z.int().min(3600).max(2592000).default(604800),
  }));
  const code = randomCode(10);
  const r = await rpc<Record<string, unknown>>("svc_create_invite", {
    p_user: c.get("user"),
    p_max_uses: b.max_uses,
    p_expires_in_s: b.expires_in_s,
    p_code_hash: await sha256Hex(code),
  });
  return c.json({ ...r, code: `${code.slice(0, 5)}-${code.slice(5)}` }, 201);
});

app.delete("/invites/:invite_id", async (c) => {
  await rpc("svc_revoke_invite", { p_user: c.get("user"), p_invite: param(c, "invite_id") });
  return c.body(null, 204);
});

app.delete("/members/:user_id", async (c) => {
  await rpc("svc_remove_member", { p_user: c.get("user"), p_target: param(c, "user_id") });
  return c.body(null, 204);
});

// ── Account and usage ─────────────────────────────────────────────────────────

app.patch("/me", async (c) => {
  const b = await body(c, z.strictObject({ display_name: DisplayName }));
  return c.json(await rpc("svc_update_me", { p_user: c.get("user"), p_display_name: b.display_name }));
});

app.delete("/me", async (c) => {
  const user = c.get("user");
  const deletePhotos = check(z.enum(["true", "false"]).default("false"), c.req.query("delete_photos")) === "true";
  const r = await rpc<{ storage_paths: string[] }>("svc_delete_me", { p_user: user, p_delete_photos: deletePhotos });
  await removeObjects(r.storage_paths);
  // If this fails, the hourly clean-up removes the auth user (it has no membership now).
  const { error } = await admin.auth.admin.deleteUser(user);
  if (error) console.error("auth user delete failed", error);
  return c.body(null, 204);
});

app.get("/usage", async (c) => {
  const u = await rpc<{ frame: Record<string, unknown> }>("svc_usage", { p_user: c.get("user") });
  return c.json({ ...u, frame: { ...u.frame, free_tier_bytes: FREE_TIER_BYTES } });
});

Deno.serve(app.fetch);
