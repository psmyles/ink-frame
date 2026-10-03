// Service-role client. RLS is bypassed, so every permission check lives in the svc_*
// SQL functions (migrations/0004_api.sql).

import { createClient } from "npm:@supabase/supabase-js@2.117.1";
import { fromPg } from "./http.ts";

export const BUCKET = "frame-images";

export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

export async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) throw fromPg(error);
  return data as T;
}

// Best effort: an object left behind is swept by /app-api/internal/maintenance.
export async function removeObjects(paths: string[]): Promise<void> {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await admin.storage.from(BUCKET).remove(paths.slice(i, i + 100));
    if (error) console.error("storage remove failed", error);
  }
}
