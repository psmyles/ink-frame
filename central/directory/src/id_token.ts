// Verifies Google and Apple ID tokens (RS256) against the providers' published keys.

export type Provider = "google" | "apple";

const ISSUERS: Record<string, Provider> = {
  "https://accounts.google.com": "google",
  "accounts.google.com": "google",
  "https://appleid.apple.com": "apple",
};

const KEYS_URL: Record<Provider, string> = {
  google: "https://www.googleapis.com/oauth2/v3/certs",
  apple: "https://appleid.apple.com/auth/keys",
};

export type Jwk = { kty: string; kid?: string; n?: string; e?: string };
export type KeySource = (provider: Provider) => Promise<Jwk[]>;

export class InvalidIdToken extends Error {}

/** The providers' keys over HTTPS. */
export const remoteKeys = (fetcher: typeof fetch = fetch): KeySource => async (provider) => {
  const res = await fetcher(KEYS_URL[provider]);
  if (!res.ok) throw new Error(`${provider} keys: HTTP ${res.status}`);
  return ((await res.json()) as { keys: Jwk[] }).keys;
};

const LEEWAY_S = 60;
const KEYS_MAX_AGE_MS = 60 * 60 * 1000;
// An unknown key ID refetches the keys (they rotate), but not more often than this.
const KEYS_MIN_REFRESH_MS = 60 * 1000;

export function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const padded = s.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (s.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

export class IdTokenVerifier {
  #cache = new Map<Provider, { at: number; keys: Map<string, CryptoKey> }>();

  /** [audiences]: the client IDs each provider's tokens may be issued to. */
  constructor(
    private readonly audiences: Record<Provider, string[]>,
    private readonly source: KeySource,
    private readonly now: () => number = Date.now,
  ) {}

  /** The provider and its stable user ID (`sub`). Throws [InvalidIdToken]. */
  async verify(token: string): Promise<{ provider: Provider; sub: string }> {
    const parts = token.split(".");
    if (parts.length !== 3) throw new InvalidIdToken("Not a JWT.");
    let header, claims;
    try {
      const text = (s: string) => JSON.parse(new TextDecoder().decode(b64urlDecode(s)));
      [header, claims] = [text(parts[0]), text(parts[1])];
    } catch {
      throw new InvalidIdToken("Not a JWT.");
    }
    if (header?.alg !== "RS256" || typeof header.kid !== "string") throw new InvalidIdToken("Unsupported algorithm.");

    const provider = ISSUERS[claims?.iss];
    if (!provider) throw new InvalidIdToken("Unknown issuer.");
    const aud: unknown[] = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (!aud.some((a) => this.audiences[provider].includes(a as string))) throw new InvalidIdToken("Wrong audience.");
    const now = this.now() / 1000;
    if (typeof claims.exp !== "number" || claims.exp < now - LEEWAY_S) throw new InvalidIdToken("Expired.");
    if (typeof claims.iat === "number" && claims.iat > now + LEEWAY_S) throw new InvalidIdToken("Issued in the future.");
    if (typeof claims.sub !== "string" || !claims.sub) throw new InvalidIdToken("No subject.");

    const key = await this.#key(provider, header.kid);
    if (!key) throw new InvalidIdToken("Unknown key.");
    let signature;
    try {
      signature = b64urlDecode(parts[2]);
    } catch {
      throw new InvalidIdToken("Bad signature.");
    }
    const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signed))) {
      throw new InvalidIdToken("Bad signature.");
    }
    return { provider, sub: claims.sub };
  }

  async #key(provider: Provider, kid: string): Promise<CryptoKey | undefined> {
    const now = this.now();
    let entry = this.#cache.get(provider);
    const stale = !entry || now - entry.at > KEYS_MAX_AGE_MS;
    if (stale || (!entry!.keys.has(kid) && now - entry!.at > KEYS_MIN_REFRESH_MS)) {
      const keys = new Map<string, CryptoKey>();
      for (const jwk of await this.source(provider)) {
        if (jwk.kty !== "RSA" || !jwk.kid || !jwk.n || !jwk.e) continue;
        keys.set(jwk.kid, await crypto.subtle.importKey(
          "jwk",
          { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
          { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
          false,
          ["verify"],
        ));
      }
      entry = { at: now, keys };
      this.#cache.set(provider, entry);
    }
    return entry!.keys.get(kid);
  }
}
