// Golden test vectors for the Dart dithering port (PLAN.md §8.4).
//   node tools/golden/gen-vectors.mjs
//
// Runs the unmodified reference/ink-frame-lab/js/dithering.js on fixed, already
// resized RGBA inputs and writes palette-index arrays to
// shared/test-vectors/dither.json. The Dart port must match them exactly (random
// mode is checked statistically instead, since it uses Math.random).

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

globalThis.ImageData = class ImageData {
  constructor(a, b, c) {
    if (a instanceof Uint8ClampedArray) {
      this.data = a;
      this.width = b;
      this.height = c;
    } else {
      this.width = a;
      this.height = b;
      this.data = new Uint8ClampedArray(a * b * 4);
    }
  }
};

const { applyErrorDiffusion, applyOrdered, applyQuantization, ED_KERNELS } = await import(
  `${root}reference/ink-frame-lab/js/dithering.js`
);

const presets = JSON.parse(readFileSync(`${root}shared/presets.json`, "utf8"));
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const palettes = Object.fromEntries(presets.palettes.map((p) => [p.id, p.colors.map((c) => hex(c.color))]));

// ── Inputs: deterministic, odd sizes so edges and serpentine rows are exercised ──
function xorshift(seed) {
  let s = seed >>> 0;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

function makeInput(name, w, h, fn) {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [r, g, b] = fn(x, y, w, h);
      const i = (y * w + x) * 4;
      data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255;
    }
  }
  return { name, width: w, height: h, data };
}

const rnd = xorshift(20260926);
const inputs = [
  // Sky-like gradients: hue across, lightness down.
  makeInput("gradient", 97, 61, (x, y, w, h) => {
    const t = x / (w - 1), u = y / (h - 1);
    return [255 * t * (1 - u) + 40 * u, 180 * (1 - Math.abs(t - 0.5) * 2) + 60 * u, 255 * (1 - t) * (1 - u * 0.5)];
  }),
  // Flat patches (skin, foliage, sky, greys) with hard edges.
  makeInput("patches", 64, 40, (x, y) => {
    const colors = [[224, 172, 140], [70, 110, 60], [120, 170, 220], [128, 128, 128], [250, 240, 200], [30, 30, 40], [200, 60, 50], [240, 200, 40]];
    return colors[(Math.floor(x / 16) + Math.floor(y / 20) * 4) % colors.length];
  }),
  // Photo-like texture: smooth waves plus seeded noise.
  makeInput("texture", 50, 31, (x, y) => {
    const n = () => (rnd() - 0.5) * 60;
    return [
      128 + 90 * Math.sin(x / 5) + n(),
      128 + 90 * Math.cos(y / 4) + n(),
      128 + 70 * Math.sin((x + y) / 7) + n(),
    ];
  }),
];

// ── Cases ──
const kernels = Object.keys(ED_KERNELS);
const cases = [];
for (const input of inputs) {
  const full = input.name !== "patches";
  for (const paletteId of full ? ["spectra6"] : ["spectra6", "gallery", "default"]) {
    cases.push({ input: input.name, palette: paletteId, mode: "quantization" });
    for (const kernel of full ? kernels : ["floydSteinberg"]) {
      for (const serpentine of [false, true]) {
        cases.push({ input: input.name, palette: paletteId, mode: "errorDiffusion", kernel, serpentine });
      }
    }
    for (const [ow, oh] of full ? [[2, 2], [4, 4], [8, 8], [16, 16], [3, 5]] : [[4, 4]]) {
      cases.push({ input: input.name, palette: paletteId, mode: "ordered", orderedW: ow, orderedH: oh });
    }
  }
}
// The other palettes on a photo-like input too.
for (const paletteId of ["gallery", "default"]) {
  cases.push({ input: "texture", palette: paletteId, mode: "errorDiffusion", kernel: "floydSteinberg", serpentine: true });
  cases.push({ input: "texture", palette: paletteId, mode: "ordered", orderedW: 4, orderedH: 4 });
}

function toIndices(img, palette) {
  const out = new Uint8Array(img.width * img.height);
  for (let i = 0; i < out.length; i++) {
    const r = img.data[i * 4], g = img.data[i * 4 + 1], b = img.data[i * 4 + 2];
    const k = palette.findIndex((c) => c[0] === r && c[1] === g && c[2] === b);
    if (k < 0) throw new Error("output colour not in palette");
    out[i] = k;
  }
  return out;
}

const byName = Object.fromEntries(inputs.map((i) => [i.name, i]));
for (const c of cases) {
  const input = byName[c.input];
  const img = new ImageData(new Uint8ClampedArray(input.data), input.width, input.height);
  const pal = palettes[c.palette];
  const out = c.mode === "quantization"
    ? applyQuantization(img, pal)
    : c.mode === "errorDiffusion"
    ? applyErrorDiffusion(img, pal, c.kernel, c.serpentine)
    : applyOrdered(img, pal, c.orderedW, c.orderedH);
  c.indices = Buffer.from(toIndices(out, pal)).toString("base64");
}

mkdirSync(`${root}shared/test-vectors`, { recursive: true });
writeFileSync(
  `${root}shared/test-vectors/dither.json`,
  JSON.stringify({
    generated_by: "tools/golden/gen-vectors.mjs from reference/ink-frame-lab/js/dithering.js",
    palettes,
    inputs: inputs.map((i) => ({ name: i.name, width: i.width, height: i.height, rgba: Buffer.from(i.data).toString("base64") })),
    cases,
  }, null, 1) + "\n",
);
console.log(`${cases.length} cases, ${inputs.length} inputs → shared/test-vectors/dither.json`);
