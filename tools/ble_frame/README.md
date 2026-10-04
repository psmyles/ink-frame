# Pretend frame

A stand-in for an Ink Frame over **real Bluetooth**, so Connect the frame
(app-flow §6, [docs/pairing.md](../../docs/pairing.md)) can be tried on a phone before
the firmware exists. It advertises as `InkFrame-XXXX`, answers the pairing service,
and hands the Wi-Fi details and pairing token to [frame_sim](../frame_sim), which
claims the frame over HTTPS and checks for photos. The photo the frame would show
appears in the window.

Run it on one device and the Ink Frame app on another (a device can't connect to
itself): the Mac here and the app on a phone, or the other way round.

```sh
cd tools/ble_frame
flutter run -d macos        # or: flutter run -d <android-device-id>
```

macOS asks once for Bluetooth permission. Then in the Ink Frame app (as the frame's
owner): **Connect the frame** → **Find the frame** → pick a network → Connect. (No
pairing prompt with the default settings; see below.)

- Wi-Fi is pretend: any password works except `wrong` (→ "the password didn't
  work"), and "Far away" is never found. After "joining", it really calls the
  frame's `device-api`.
- **Require pairing** (default off) makes every characteristic need an encrypted link,
  like the real frame. A Mac refused an Android phone's pairing outright when it was
  on, and neither a Mac nor a phone can use the frame's fixed code, so it's off: the
  pretend frame tests everything except the pairing itself, which needs the firmware
  (4b). The 6 digits in the window are for show.
- **Model** picks the `model_id` it reports, to try "This frame is a …".
- **Check now** is the green button (sync, then show the newest photo); **Pair again**
  is holding it 3 s; **Reset** is holding it 10 s (new `hw_id`, forgets the frame).
- State (frame_sim's `config.json` and cache) lives in the app's support folder.
