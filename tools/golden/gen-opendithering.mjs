// Golden vectors for the Dart port of opendithering's pipeline and Auto-tune
// (reference/opendithering, MIT). Runs the unmodified TypeScript under Node
// (ts-hooks.mjs) on fixed, pre-sized RGBA inputs.
//   node tools/golden/gen-opendithering.mjs
// → shared/test-vectors/opendithering.json

import { register } from "node:module";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

globalThis.ImageData = class ImageData {
  constructor(a, b, c) {
    if (a instanceof Uint8ClampedArray) {
      this.data = a; this.width = b; this.height = c;
    } else {
      this.width = a; this.height = b; this.data = new Uint8ClampedArray(a * b * 4);
    }
  }
};

register("./ts-hooks.mjs", import.meta.url);
const od = `${root}reference/opendithering/src/`;
const { runPipeline } = await import(`${od}processing/pipeline.ts`);
const { autoExpose } = await import(`${od}processing/autoexpose.ts`);
const { colorTune } = await import(`${od}processing/colortune.ts`);
const { hueTune } = await import(`${od}processing/huetune.ts`);
const { PRESETS } = await import(`${od}types.ts`);
const { getPalette } = await import(`${od}palettes/index.ts`);

// ── Inputs: photo-like, deterministic ──
function xorshift(seed) {
  let s = seed >>> 0;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}
function makeInput(name, w, h, fn) {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b] = fn(x, y, w, h); const i = (y * w + x) * 4;
    data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255;
  }
  return { name, width: w, height: h, data };
}
const rnd = xorshift(424242);
const inputs = [
  // Landscape: sky gradient, sun, green hills, darker foreground, noise.
  makeInput("landscape", 96, 58, (x, y, w, h) => {
    const n = () => (rnd() - 0.5) * 24;
    const hill = h * 0.55 + 6 * Math.sin(x / 9);
    if (Math.hypot(x - w * 0.75, y - h * 0.25) < 7) return [250 + n(), 220 + n(), 120 + n()];
    if (y < hill) return [110 + y * 1.5 + n(), 160 + y + n(), 230 - y + n()];
    const t = (y - hill) / (h - hill);
    return [60 + 40 * t + n(), 120 - 50 * t + n(), 50 + n()];
  }),
  // Portrait-ish: warm skin tones, dark hair, muted background, red top.
  makeInput("portrait", 80, 48, (x, y, w, h) => {
    const n = () => (rnd() - 0.5) * 16;
    const dx = (x - w / 2) / 14, dy = (y - h * 0.45) / 18;
    if (dx * dx + dy * dy < 1) return [225 + n() - 30 * dy, 170 + n() - 30 * dy, 140 + n()];
    if (dx * dx + (dy + 0.6) ** 2 < 1.6 && y < h * 0.4) return [50 + n(), 35 + n(), 30 + n()];
    if (y > h * 0.8) return [190 + n(), 40 + n(), 50 + n()];
    return [150 + x + n(), 150 + n(), 140 + y + n()];
  }),
];

const toData = (i) => new ImageData(new Uint8ClampedArray(i.data), i.width, i.height);
const b64 = (u8) => Buffer.from(u8).toString("base64");

function indicesOf(img, palette) {
  const out = new Uint8Array(img.width * img.height);
  for (let i = 0; i < out.length; i++) {
    const r = img.data[i * 4], g = img.data[i * 4 + 1], b = img.data[i * 4 + 2];
    const k = palette.colors.findIndex((c) => c.measured[0] === r && c.measured[1] === g && c.measured[2] === b);
    if (k < 0) throw new Error("not a palette colour");
    out[i] = k;
  }
  return out;
}

const palettes = {
  "spectra6-guysie": getPalette("spectra6-guysie"),
  "spectra6-epdoptimize": getPalette("spectra6-epdoptimize"),
  "acep-epdoptimize": getPalette("acep-epdoptimize"),
};

// ── Pipeline cases: presets and variations ──
const B = PRESETS.balanced;
const settingsCases = {
  balanced: B,
  vivid: PRESETS.vivid,
  soft: PRESETS.soft,
  "balanced-contrast": { ...B, toneMode: "contrast", contrast: 1.2 },
  "balanced-cielab": { ...B, errorSpace: "cielab", distSpace: "cielab" },
  "balanced-oklab-chroma": { ...B, errorSpace: "oklab-chroma", distSpace: "oklab-chroma" },
  "balanced-rgb-err-oklab-dist": { ...B, errorSpace: "rgb", distSpace: "oklab" },
  "balanced-graded": { ...B, exposure: 1.1, redGain: 1.05, blueGain: 0.9, hueSatBands: [1.3, 0.8, 1.1, 1, 1.5, 0.7], shadowBoost: 0.2, highlightCompress: 2 },
  "balanced-clarity": { ...B, clarity: 0.6, clarityRadius: 2 },
  "balanced-variance-half": { ...B, localVarianceDetection: true, ditherStrength: 0.8 },
  atkinson: { ...B, ditherAlgorithm: "atkinson" },
  jarvis: { ...B, ditherAlgorithm: "jarvis", serpentine: false },
  burkes: { ...B, ditherAlgorithm: "burkes" },
  sierra: { ...B, ditherAlgorithm: "sierra" },
};

const pipelineCases = [];
for (const input of inputs) {
  for (const [name, settings] of Object.entries(settingsCases)) {
    const paletteId = name === "vivid" ? "acep-epdoptimize" : "spectra6-guysie";
    const pal = palettes[paletteId];
    const r = runPipeline({ source: toData(input), srcWidth: input.width, srcHeight: input.height, dstWidth: input.width, dstHeight: input.height, resizeMode: "cover", palette: pal, settings: { ...settings } });
    pipelineCases.push({ input: input.name, palette: paletteId, name, settings, indices: b64(indicesOf(r.measured, pal)) });
  }
}

// ── Auto-tune cases: autoExpose → colorTune → hueTune (as main.ts does) ──
const autoCases = [];
for (const input of inputs) {
  for (const paletteId of ["spectra6-guysie", "spectra6-epdoptimize"]) {
    const pal = palettes[paletteId];
    const base = { source: toData(input), srcWidth: input.width, srcHeight: input.height, dstWidth: input.width, dstHeight: input.height, resizeMode: "cover", palette: pal };
    let settings = { ...B };
    const e = autoExpose({ ...base, settings });
    settings = { ...settings, exposure: e.exposure, saturation: e.saturation, contrast: e.contrast, strength: e.strength, shadowBoost: e.shadowBoost, highlightCompress: e.highlightCompress, midpoint: e.midpoint, redGain: e.redGain, greenGain: e.greenGain, blueGain: e.blueGain, compressDynamicRange: e.compressDynamicRange };
    const afterExpose = { ...settings };
    const c = colorTune({ ...base, source: toData(input), settings });
    settings = { ...settings, saturation: c.saturation, redGain: c.redGain, greenGain: c.greenGain, blueGain: c.blueGain };
    const afterColor = { ...settings };
    const h = hueTune({ ...base, source: toData(input), settings });
    settings = { ...settings, hueSatBands: h.hueSatBands };
    const r = runPipeline({ ...base, source: toData(input), settings });
    autoCases.push({
      input: input.name, palette: paletteId,
      afterExpose, afterColor, final: settings,
      colorIterations: c.debug.iterationsRun, hueIterations: h.debug.iterationsRun,
      indices: b64(indicesOf(r.measured, pal)),
    });
  }
}

writeFileSync(`${root}shared/test-vectors/opendithering.json`, JSON.stringify({
  generated_by: "tools/golden/gen-opendithering.mjs from reference/opendithering (MIT)",
  palettes: Object.fromEntries(Object.entries(palettes).map(([k, p]) => [k, p.colors.map((c) => ({ name: c.name, measured: c.measured, ideal: c.ideal }))])),
  inputs: inputs.map((i) => ({ name: i.name, width: i.width, height: i.height, rgba: b64(i.data) })),
  pipeline: pipelineCases,
  autotune: autoCases,
}, null, 1) + "\n");
console.log(`${pipelineCases.length} pipeline cases, ${autoCases.length} auto-tune cases → shared/test-vectors/opendithering.json`);
for (const a of autoCases) console.log(` ${a.input} ${a.palette}: exposure ${a.final.exposure.toFixed(3)} strength ${a.final.strength.toFixed(3)} gains ${[a.final.redGain, a.final.greenGain, a.final.blueGain].map((v) => v.toFixed(3))} bands ${a.final.hueSatBands.map((v) => v.toFixed(2))} (color ${a.colorIterations}, hue ${a.hueIterations} iterations)`);
