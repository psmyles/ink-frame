// Error type, the contract's error-code → HTTP status table, and request helpers.

import type { Context } from "npm:hono@4.13.8";
import { z } from "npm:zod@4.6.5";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

// Every error code in shared/api/openapi.yaml.
const STATUS: Record<string, number> = {
  invalid_request: 400,
  unauthenticated: 401,
  invalid_pairing_token: 401,
  invalid_device_secret: 401,
  not_project_member: 403,
  not_frame_member: 403,
  not_frame_owner: 403,
  not_admin: 403,
  not_uploader: 403,
  not_allowed: 403,
  cannot_remove_owner: 403,
  cannot_remove_self: 403,
  not_found: 404,
  frame_not_found: 404,
  image_not_found: 404,
  member_not_found: 404,
  invite_not_found: 404,
  invalid_invite: 404,
  hw_id_conflict: 409,
  duplicate_image: 409,
  not_uploaded: 409,
  conflict: 409,
  frame_removed: 410,
  too_large: 413,
  unknown_model: 422,
  dimension_mismatch: 422,
  quota_exceeded: 422,
  invalid_png: 422,
  size_mismatch: 422,
  unknown_timezone: 422,
  quiet_hours_incomplete: 422,
  display_name_required: 422,
};

export function fail(code: string, message: string, details?: Record<string, unknown>): never {
  throw new ApiError(STATUS[code] ?? 500, code, message, details);
}

type PgError = { code?: string; message: string; hint?: string | null; details?: string | null };

// svc_* functions raise P0001 with message = code, hint = text, detail = JSON.
export function fromPg(e: PgError): ApiError {
  if (e.code === "P0001" && STATUS[e.message]) {
    let details: Record<string, unknown> | undefined;
    if (e.details) {
      try {
        details = JSON.parse(e.details);
      } catch { /* leave undefined */ }
    }
    return new ApiError(STATUS[e.message], e.message, e.hint ?? e.message, details);
  }
  if (e.code === "23505") return new ApiError(409, "conflict", "A concurrent change conflicted; try again.");
  console.error("database error", e);
  return new ApiError(500, "internal", "Internal error.");
}

export function errorResponse(c: Context, err: unknown): Response {
  if (err instanceof ApiError) {
    const error: Record<string, unknown> = { code: err.code, message: err.message };
    if (err.details) error.details = err.details;
    // deno-lint-ignore no-explicit-any
    return c.json({ error }, err.status as any);
  }
  console.error("unhandled", err);
  return c.json({ error: { code: "internal", message: "Internal error." } }, 500);
}

export function bearer(c: Context): string | undefined {
  const m = /^Bearer\s+(.+)$/i.exec(c.req.header("Authorization") ?? "");
  return m?.[1].trim() || undefined;
}

export async function body<T extends z.ZodType>(c: Context, schema: T): Promise<z.infer<T>> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    fail("invalid_request", "Body must be JSON.");
  }
  return check(schema, raw);
}

export function check<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const r = schema.safeParse(value);
  if (!r.success) {
    const issue = r.error.issues[0];
    fail("invalid_request", issue.message, { field: issue.path.join(".") });
  }
  return r.data;
}
