// device-api: called by frames and tools/frame_sim (PLAN.md §7.3,
// shared/api/openapi.yaml). Auth is the device secret, not a JWT.

import { Hono } from "npm:hono@4.13.8";
import { z } from "npm:zod@4.6.5";
import { base64url, normalizeCode, randomBytes, sha256Hex } from "../_shared/crypto.ts";
import { admin, BUCKET, rpc } from "../_shared/db.ts";
import { ApiError, bearer, body, errorResponse, fail } from "../_shared/http.ts";
import { FwVersion, HwId, ModelId, Uuid } from "../_shared/schemas.ts";
import { TZ_POSIX } from "../_shared/tz.ts";

const app = new Hono().basePath("/device-api");
app.onError((err, c) => errorResponse(c, err));
app.notFound((c) => errorResponse(c, new ApiError(404, "not_found", "No such endpoint.")));

const ClaimBody = z.strictObject({
  pairing_token: z.string().transform(normalizeCode).pipe(z.string().regex(/^[0-9A-HJKMNP-TV-Z]{26}$/)),
  hw_id: HwId,
  model_id: ModelId,
  fw_version: FwVersion,
});

app.post("/claim", async (c) => {
  const b = await body(c, ClaimBody);
  const secret = base64url(randomBytes(32));
  const frameId = await rpc<string>("svc_claim_frame", {
    p_token_hash: await sha256Hex(b.pairing_token),
    p_hw_id: b.hw_id,
    p_model_id: b.model_id,
    p_fw_version: b.fw_version,
    p_secret_hash: await sha256Hex(secret),
  });
  return c.json({ frame_id: frameId, device_secret: secret });
});

const SyncBody = z.strictObject({
  manifest_version: z.int().min(0),
  fw_version: FwVersion,
  battery_pct: z.int().min(0).max(100).nullable().optional(),
  rssi: z.int().min(-127).max(0).nullable().optional(),
  sd_total_bytes: z.int().min(0).nullable().optional(),
  sd_free_bytes: z.int().min(0).nullable().optional(),
  cache_bytes: z.int().min(0).nullable().optional(),
  local_ids: z.array(Uuid).max(2000),
});

type SyncRow = {
  manifest_version: number;
  settings: Record<string, unknown> & { timezone: string };
  images: { id: string; sha256: string; bytes: number; position: number; storage_path: string }[] | null;
};

app.post("/sync", async (c) => {
  const secret = bearer(c) ?? fail("invalid_device_secret", "Missing device secret.");
  const b = await body(c, SyncBody);
  const r = await rpc<SyncRow>("svc_sync_frame", {
    p_secret_hash: await sha256Hex(secret),
    p_manifest_version: b.manifest_version,
    p_fw_version: b.fw_version,
    p_battery_pct: b.battery_pct ?? null,
    p_rssi: b.rssi ?? null,
    p_sd_total_bytes: b.sd_total_bytes ?? null,
    p_sd_free_bytes: b.sd_free_bytes ?? null,
    p_cache_bytes: b.cache_bytes ?? null,
  });

  const { timezone, ...settings } = r.settings;
  const res: Record<string, unknown> = {
    manifest_version: r.manifest_version,
    settings: { ...settings, tz_posix: TZ_POSIX[timezone] ?? "UTC0" },
    server_time: Math.floor(Date.now() / 1000),
  };

  if (r.images) {
    const local = new Set(b.local_ids);
    const missing = r.images.filter((i) => !local.has(i.id)).map((i) => i.storage_path);
    const urls = new Map<string, string>();
    if (missing.length) {
      const { data, error } = await admin.storage.from(BUCKET).createSignedUrls(missing, 3600);
      if (error) throw error;
      for (const s of data) if (s.signedUrl && s.path) urls.set(s.path, s.signedUrl);
    }
    // An image whose object is gone can't be downloaded; leave it out rather than
    // send an entry the frame can never fill.
    res.images = r.images.flatMap((i) => {
      const entry = { id: i.id, sha256: i.sha256, bytes: i.bytes, position: i.position };
      if (local.has(i.id)) return [entry];
      const url = urls.get(i.storage_path);
      if (!url) {
        console.error("no object for image", i.id);
        return [];
      }
      return [{ ...entry, url }];
    });
  }
  return c.json(res);
});

Deno.serve(app.fetch);
