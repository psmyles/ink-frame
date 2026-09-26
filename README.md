# Ink Frame

Photo frames on e-ink displays, filled from your phone.

Ink Frame follows on from [ink-frame-lab](https://github.com/psmyles/ink-frame-lab), a web tool for cropping and dithering images for e-ink panels. Instead of uploading PNGs over the frame's own Wi-Fi hotspot, a family uses the app:

- **App** (Flutter: iOS, Android, desktop). Crops, dithers and compresses photos on the device, then uploads them to the frame.
- **Backend.** Each frame has its own Supabase project on the free tier, in the Supabase account of the person who sets it up. The app sets it up with an in-app wizard. Others sign in with Google or Apple and join by invite.
- **Frame firmware** (ESP32-S3, Seeed reTerminal E1002 first). The frame is connected over Bluetooth and checks for new photos once a day, or when you press the green button. It keeps a copy of its photos on its SD card and shows them offline. Firmware updates arrive over the air from a signed feed.

## Status

In development. See [PLAN.md](PLAN.md) for the full design, phases and progress.

## Repository layout

| Path | Contents |
|---|---|
| `shared/` | Device and palette presets, the API contract (`api/openapi.yaml`), dithering test vectors |
| `backend/supabase/` | Database migrations, Edge Functions (`device-api`, `app-api`), tests |
| `app/` | Flutter app |
| `firmware/` | PlatformIO firmware |
| `tools/` | Golden test vector generator, frame simulator, dev scripts |
| `central/` | GitHub Pages site: invite and sign-in pages, firmware update feed |
| `docs/` | Design notes and spike findings |
| `reference/` | Read-only source files copied from ink-frame-lab |
