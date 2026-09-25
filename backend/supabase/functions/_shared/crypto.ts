// Tokens, codes and hashes. Only hashes are stored; the plain values leave the
// server once, in the response that creates them.

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

// n random Crockford base32 characters (5 bits each; 256 is a multiple of 32, so
// `byte & 31` is unbiased).
export function randomCode(n: number): string {
  return Array.from(randomBytes(n), (b) => CROCKFORD[b & 31]).join("");
}

// Crockford decoding rules: case-insensitive, I/L read as 1, O as 0; hyphens and
// spaces ignored.
export function normalizeCode(s: string): string {
  return s.toUpperCase().replace(/[\s-]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
}

export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(data: string | Uint8Array<ArrayBuffer>): Promise<string> {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
