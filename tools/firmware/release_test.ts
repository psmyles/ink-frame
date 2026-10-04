// deno test tools/firmware/
import { assert, assertEquals } from "jsr:@std/assert@1";
import { keysHeaderText, listedKeys, publicPoint, type Release, sign, signedText } from "./release.ts";

const release: Release = {
  model_id: "reterminal-e1002",
  version: "0.2.0",
  url: "https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin",
  size: 1310720,
  sha256: "9b74c9897bac770ffc029102a200c5de9b74c9897bac770ffc029102a200c5de",
  min_battery_pct: 30,
  rollout_percent: 100,
};

Deno.test("the signed text is the firmware's (firmware/test/test_firmware_update)", () => {
  assertEquals(
    signedText(release),
    "inkframe-firmware 1\n" +
      "model reterminal-e1002\n" +
      "version 0.2.0\n" +
      "url https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin\n" +
      "size 1310720\n" +
      "sha256 9b74c9897bac770ffc029102a200c5de9b74c9897bac770ffc029102a200c5de\n" +
      "min_battery_pct 30\n" +
      "rollout_percent 100\n",
  );
});

Deno.test("a signature verifies with the listed public key, and not after a change", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const signed = await sign(release, pair.privateKey);
  assertEquals(signed.signature!.length, 128); // r || s
  const point = await publicPoint(pair.privateKey);
  const listed = listedKeys(keysHeaderText([point]));
  assertEquals(listed, [Array.from(point, (b) => b.toString(16).padStart(2, "0")).join("")]);

  const verifyKey = await crypto.subtle.importKey("raw", point, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const sig = Uint8Array.from(signed.signature!.match(/../g)!, (h) => parseInt(h, 16));
  const check = (r: Release) =>
    crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, verifyKey, sig, new TextEncoder().encode(signedText(r)));
  assert(await check(release));
  assert(!(await check({ ...release, rollout_percent: 50 })));
});
