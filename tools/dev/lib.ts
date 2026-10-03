// Shared helpers for tools/dev scripts.

export type Env = { token: string; ref: string };

// Environment variables win; otherwise backend/.env.local (KEY=value lines).
export async function loadEnv(): Promise<Env> {
  const file: Record<string, string> = {};
  try {
    const text = await Deno.readTextFile(new URL("../../backend/.env.local", import.meta.url));
    for (const line of text.split("\n")) {
      const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
      if (m) file[m[1]] = m[2];
    }
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
  }
  const get = (k: string) => Deno.env.get(k) ?? file[k];
  const token = get("SUPABASE_ACCESS_TOKEN");
  const ref = get("SUPABASE_PROJECT_REF");
  if (!token || !ref) throw new Error("SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF are required");
  return { token, ref };
}

// Management API call. Throws on non-2xx; returns parsed JSON (or null when empty).
export async function mgmt<T = any>(
  env: Pick<Env, "token">,
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  const res = await fetch(`https://api.supabase.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.token}`,
      ...(body !== undefined && !(body instanceof FormData) ? { "Content-Type": "application/json" } : {}),
    },
    body: body === undefined ? undefined : body instanceof FormData ? body : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new MgmtError(res.status, `${method} ${path} → ${res.status}: ${text}`);
  return (text ? JSON.parse(text) : null) as T;
}

export class MgmtError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

// Runs SQL through the Management API as postgres. Multiple statements are allowed.
export async function sql<T = Record<string, unknown>>(env: Env, query: string): Promise<T[]> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${env.ref}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`SQL failed (${res.status}): ${text}`);
  return JSON.parse(text) as T[];
}

// The Google/Apple sign-in settings every frame's project gets (shared/oauth-clients.json):
// Google with the web client first and the others allowed too; Apple with the
// bundle ID (native sign-in needs no secret). The iOS/macOS Google SDK puts its own
// nonce in the ID token, which the app can't pass on, so Google skips the nonce check.
export async function authProviders(): Promise<Record<string, unknown>> {
  const c = JSON.parse(await Deno.readTextFile(new URL("../../shared/oauth-clients.json", import.meta.url)));
  const g = c.google as Record<string, string | null>;
  // Supabase keeps every allowed ID in client_id as one comma-separated list
  // (docs/spikes/b-auth-config.md); the first is the main one.
  const ids = [g.web, g.ios, g.desktop, g.android].filter((v): v is string => !!v);
  return {
    external_google_enabled: true,
    external_google_client_id: ids.join(","),
    external_google_skip_nonce_check: true,
    external_apple_enabled: true,
    external_apple_client_id: c.apple.bundleId,
  };
}
