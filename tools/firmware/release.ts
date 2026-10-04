// Firmware releases (docs/ota.md): the signing key, and the signed manifest frames read
// from the feed.
//
//   deno run --allow-read --allow-write tools/firmware/release.ts keygen
//     A new key pair. The private key goes into firmware/fw-signing-key.pem (gitignored;
//     keep a copy somewhere safe and add it as the GitHub secret FW_SIGNING_KEY), the
//     public key into firmware/src/net/ota_keys.h. Refuses to replace an existing key
//     file: frames only trust the keys they were built with.
//
//   deno run --allow-read --allow-write --allow-env tools/firmware/release.ts sign \
//       --bin firmware.bin --version 0.2.0 --out feed \
//       [--model reterminal-e1002] [--url-base https://psmyles.github.io/ink-frame/firmware] \
//       [--rollout 100] [--min-battery 30] [--key firmware/fw-signing-key.pem]
//     Writes feed/<model>/manifest.json and feed/<model>/<version>.bin. The key is the PEM
//     in FW_SIGNING_KEY, else --key. Refuses a key that ota_keys.h doesn't list.

import { parseArgs } from "jsr:@std/cli@1/parse-args";

const root = new URL("../../", import.meta.url);
const keysHeader = new URL("firmware/src/net/ota_keys.h", root);
export const FEED_URL = "https://psmyles.github.io/ink-frame/firmware";

export interface Release {
  model_id: string;
  version: string;
  url: string;
  size: number;
  sha256: string;
  min_battery_pct: number;
  rollout_percent: number;
  signature?: string;
}

/** The text the signature covers; the firmware builds the same (core/firmware_update.cpp). */
export function signedText(r: Release): string {
  return [
    "inkframe-firmware 1",
    `model ${r.model_id}`,
    `version ${r.version}`,
    `url ${r.url}`,
    `size ${r.size}`,
    `sha256 ${r.sha256}`,
    `min_battery_pct ${r.min_battery_pct}`,
    `rollout_percent ${r.rollout_percent}`,
    "",
  ].join("\n");
}

const hex = (b: ArrayBuffer | Uint8Array) =>
  Array.from(b instanceof Uint8Array ? b : new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
const fromB64 = (s: string) => Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/") + "==".slice(0, (4 - s.length % 4) % 4)), (c) => c.charCodeAt(0));
const ecdsa = { name: "ECDSA", namedCurve: "P-256" } as const;

export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return await crypto.subtle.importKey("pkcs8", fromB64(body), ecdsa, true, ["sign"]);
}

/** The uncompressed public point (65 bytes) of a private key. */
export async function publicPoint(key: CryptoKey): Promise<Uint8Array<ArrayBuffer>> {
  const jwk = await crypto.subtle.exportKey("jwk", key);
  return new Uint8Array([4, ...fromB64(jwk.x!), ...fromB64(jwk.y!)]);
}

export async function sign(r: Release, key: CryptoKey): Promise<Release> {
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signedText(r)));
  return { ...r, signature: hex(sig) }; // r || s, 64 bytes
}

/** The keys ota_keys.h lists, as hex. */
export function listedKeys(header: string): string[] {
  return [...header.matchAll(/\{((?:\s*0x[0-9a-fA-F]{2},?)+)\s*\}/g)].map((m) =>
    [...m[1].matchAll(/0x([0-9a-fA-F]{2})/g)].map((b) => b[1].toLowerCase()).join("")
  );
}

export function keysHeaderText(points: Uint8Array[]): string {
  const rows = points.map((p) => {
    const bytes = Array.from(p, (b) => `0x${b.toString(16).padStart(2, "0")}`);
    const lines = [];
    for (let i = 0; i < bytes.length; i += 12) lines.push(`     ${bytes.slice(i, i + 12).join(", ")}`);
    return `    {\n${lines.join(",\n")}},`;
  });
  return `// Public keys that sign firmware releases (docs/ota.md): ECDSA P-256, uncompressed
// points. Written by tools/firmware/release.ts keygen; the private key is the GitHub
// secret FW_SIGNING_KEY. When replacing the key, list the new one next to the old one
// until every frame runs a firmware that knows it.
#pragma once
#include <stdint.h>

static const uint8_t kReleaseKeys[][65] = {
${rows.join("\n")}
};
`;
}

async function keygen(keyPath: string) {
  try {
    await Deno.stat(keyPath);
    throw new Error(`${keyPath} exists; frames trust the key they were built with. Move it away first if you really mean it.`);
  } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
  }
  const pair = await crypto.subtle.generateKey(ecdsa, true, ["sign", "verify"]) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n");
  await Deno.writeTextFile(keyPath, `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, { mode: 0o600 });
  const point = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  await Deno.writeTextFile(keysHeader, keysHeaderText([point]));
  console.log(`private key → ${keyPath} (never printed; add it as the GitHub secret FW_SIGNING_KEY)`);
  console.log(`public key → firmware/src/net/ota_keys.h (${hex(point).slice(0, 16)}…)`);
}

async function signCommand(a: Record<string, string>) {
  for (const k of ["bin", "version", "out"]) if (!a[k]) throw new Error(`--${k} is needed`);
  if (!/^\d+\.\d+\.\d+$/.test(a.version)) throw new Error(`version ${a.version}: MAJOR.MINOR.PATCH`);
  let pem = Deno.env.get("FW_SIGNING_KEY");
  if (!pem) {
    const path = a.key ?? new URL("firmware/fw-signing-key.pem", root).pathname;
    try {
      pem = await Deno.readTextFile(path);
    } catch {
      throw new Error(`no signing key: set FW_SIGNING_KEY (the GitHub secret) or pass --key (default ${path})`);
    }
  }
  const key = await importPrivateKey(pem);
  const point = hex(await publicPoint(key));
  if (!listedKeys(await Deno.readTextFile(keysHeader)).includes(point)) {
    throw new Error("this key isn't in firmware/src/net/ota_keys.h, so no frame would accept the release");
  }
  const model = a.model ?? "reterminal-e1002";
  const bin = await Deno.readFile(a.bin);
  const release = await sign({
    model_id: model,
    version: a.version,
    url: `${(a["url-base"] ?? FEED_URL).replace(/\/$/, "")}/${model}/${a.version}.bin`,
    size: bin.length,
    sha256: hex(await crypto.subtle.digest("SHA-256", bin)),
    min_battery_pct: Number(a["min-battery"] ?? 30),
    rollout_percent: Number(a.rollout ?? 100),
  }, key);
  if (!(release.rollout_percent >= 0 && release.rollout_percent <= 100)) throw new Error("--rollout: 0–100");
  const dir = `${a.out}/${model}`;
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeFile(`${dir}/${a.version}.bin`, bin);
  await Deno.writeTextFile(`${dir}/manifest.json`, JSON.stringify(release, null, 2) + "\n");
  console.log(`${dir}/manifest.json: ${model} ${a.version}, ${bin.length} bytes, rollout ${release.rollout_percent} %`);
}

if (import.meta.main) {
  const [command, ...rest] = Deno.args;
  const a = parseArgs(rest, { string: ["bin", "version", "out", "model", "url-base", "rollout", "min-battery", "key"] });
  if (command === "keygen") await keygen(a.key ?? new URL("firmware/fw-signing-key.pem", root).pathname);
  else if (command === "sign") await signCommand(a as unknown as Record<string, string>);
  else {
    console.error("usage: release.ts keygen | sign --bin <file> --version <x.y.z> --out <dir> [options] (see the top of this file)");
    Deno.exit(64);
  }
}
