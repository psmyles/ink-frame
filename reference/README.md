# Reference sources (read-only)

Copied from [psmyles/ink-frame-lab](https://github.com/psmyles/ink-frame-lab) at commit `c131297` so sessions working in this repo don't need that repo. **Do not edit these files.** They are the specification the new code is ported from.

| File | Used for |
|---|---|
| `ink-frame-lab/js/dithering.js` | Source of the Dart dithering port and the golden test vectors (PLAN.md §8.3) |
| `ink-frame-lab/js/export.js` | `getCroppedCanvas()`: crop and center-crop rules for the app's crop step |
| `opendithering/` | [GuySie/opendithering](https://github.com/GuySie/opendithering) (MIT, see its `LICENSE`) at commit `0de40cb`: `src/processing/` (pipeline, tone, colour spaces, Auto-tune), `src/dithering/`, `src/palettes/`, `src/types.ts`. Spec for `app/lib/imaging/{color_space,tone,od_pipeline,autotune}.dart`; vectors from `tools/golden/gen-opendithering.mjs` |
| `ink-frame-lab/presets.json` | Device models and palettes. Seed data for `device_models` / `palettes` (copied to `shared/presets.json`) |
| `ink-frame-lab/firmware/reTerminal_E1002_DigitalFrame.ino` | Current standalone firmware (SD + hotspot). Source of the PlatformIO port (PLAN.md §9) |
| `ink-frame-lab/firmware/Firmware installation instructions.md` | Current Arduino IDE settings (board, PSRAM, libraries) |

Note: ink-frame-lab's own CLAUDE.md mentions `palettes.json` / `loadPalettes()`, but that is out of date. The code uses `presets.json` / `loadPresets()`, which holds both `devices` and `palettes`.
