# Panel colour calibration

The Spectra 6 `color` values in `shared/presets.json` describe how each ink really looks on
the panel. Automatic dithers against them and the app's preview shows them, so when they
are off, the frame and the preview disagree (with inks modelled too dark, Automatic puts
down more coloured dots than it needs and pictures come out more colourful than the
preview).

## What's here
- `make_patterns.py` writes `patterns/` (gitignored):
  - `1-inks.png`, `2-mixes.png`: only the six inks, drawn as they are (the inks alone, and
    two inks mixed dot by dot).
  - `photo-colorchecker.png`, `photo-memory-colours.png`, `photo-ramps.png`: charts with
    known colours that the app dithers like a photo.
- `colours/*.json`: sets of panel colours that were tried (`{"red": "#76231F", …}`).
- `app/tool/calibration_render.dart`: the app's processing (Automatic) on the computer with
  any set of colours. It writes what the app would upload and the app's preview of it.
- `firmware/tools/console.py show`: draws a PNG on the frame over USB (developer firmware).

## Trying a set of colours
```sh
python3 tools/calibration/make_patterns.py
cd app && dart run tool/calibration_render.dart --colours ../tools/calibration/colours/<set>.json \
  ../tools/calibration/patterns/<set> ../tools/calibration/patterns/photo-colorchecker.png
cd .. && PY=$(pio system info --json-output | python3 -c 'import json,sys; print(json.load(sys.stdin)["python_exe"]["value"])')
$PY firmware/tools/console.py show tools/calibration/patterns/<set>/photo-colorchecker.frame.png --minutes 60
```
Compare the frame with the original chart and with `<name>.preview.png` on a screen. Two sets
are easiest to judge in one picture: take the left half of each patch from one render and
the right half from the other. When a set looks right, copy it into `shared/presets.json`,
then run `tools/dev/gen-seed.ts` and `tools/dev/bundle-backend.ts`. Existing albums get it
when the owner's app offers **Update** (the seed is part of the backend's fingerprint).
Photos already on the frame keep the dots they were given.

## What we found (2026-10-04, the user's E1002)
- The earlier values (`#1F2226 #B9C7C9 #233F8E #35563A #62201E #C1BB1E`, from EPDOptimize)
  made the frame more colourful than the preview. A phone photo of `1-inks.png` (each ink
  relative to the screen white next to it, the white plastic around the screen as pure
  white) gave `colours/photo-2026-10-04.json`. In it every ink is lighter, the black is
  slightly purple and the green is teal.
- Phone photos aren't a measuring instrument. The camera adds saturation and tone-maps each
  part of the picture its own way. In a photo with the original chart on a monitor, its
  greys 160 and 200 came out almost equally bright.
- A split ColorChecker (left half of each patch: the earlier values; right half: the photo's)
  looked best halfway between, to the user's eye. So the presets now hold
  `colours/midway-2026-10-04.json`, halfway in OKLab.
- The colorimeter values that opendithering publishes (`spectra6-guysie` in
  `app/test/imaging/fidelity_bench_test.dart`, another panel) have the same hues as the
  photo (purple black, teal green). Relative to white, their red and blue are as light as
  the photo's or lighter. So if the halfway set ever looks dull on real photos, try a step
  toward the photo's values rather than back.
- Dots of black mix as light does: a ½ checkerboard matched the linear-light average. Solid
  lines of the same coverage looked darker.
