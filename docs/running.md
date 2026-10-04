# Running Ink Frame

How to start the app on each platform, and the pretend frame for trying **Connect
the frame** over real Bluetooth.

Run the app's commands from `app/`. `--dart-define=DEV_MODE=true` starts the app
with developer mode on, which adds:

- email sign-in (it works on dev projects only);
- **Connect with a code (developer)**;
- **Account → Check batteries now**;
- extra details in error messages.

Leave it out to see what everyone else sees. You can also turn developer mode on
inside the app: tap the version number in **Account** 7 times.

```sh
cd app
flutter devices          # lists connected phones and their IDs
```

## Mac

```sh
flutter run -d macos --dart-define=DEV_MODE=true
```

## iPhone

**Once per iPhone:**

1. Connect it with a cable, unlock it and tap **Trust**.
2. Turn on **Settings → Privacy & Security → Developer Mode**, then restart the iPhone.
3. In **Xcode → Settings → Accounts**, sign in with the Apple account for team
   `48QFANT8RD`.

**Run it:**

```sh
flutter run -d 00008150-000A2C911EF0401C --dart-define=DEV_MODE=true   # Chandan's iPhone 17 Pro
```

- **Signing or "device not registered" error:** open `ios/Runner.xcworkspace` in
  Xcode, pick the iPhone at the top, and press **Run** once. After that,
  `flutter run` works.
- **Debug builds only start from `flutter run` or Xcode.** To keep using the app
  after unplugging, install a release build:

  ```sh
  flutter run --release -d 00008150-000A2C911EF0401C --dart-define=DEV_MODE=true
  ```

## Android

**Once per phone:** turn on **Developer options → USB debugging**, connect the phone
with a cable, and allow the computer when the phone asks.

```sh
flutter run -d <android-id> --dart-define=DEV_MODE=true
flutter run --release -d <android-id> --dart-define=DEV_MODE=true   # stays installed, runs without the computer
```

## Windows

Run these on a Windows PC, from `app\`. Google sign-in on Windows needs
`app\.env.local`, which holds `GOOGLE_DESKTOP_CLIENT_SECRET=...`. That file is
gitignored, so copy it from the Mac. Sign in with Apple isn't available on Windows.

```sh
flutter run -d windows --dart-define=DEV_MODE=true --dart-define-from-file=.env.local
```

## Linux (untested)

```sh
flutter run -d linux --dart-define=DEV_MODE=true --dart-define-from-file=.env.local
```

## While it runs

The terminal shows the app's log. Keys:

- `r`: reload the code (hot reload).
- `R`: restart the app.
- `q`: quit.

## Building app files

Add the same `--dart-define` options to a build when you want them in it.

| Platform | Command | Result |
|---|---|---|
| macOS | `flutter build macos` | `build/macos/Build/Products/Release/ink_frame.app` |
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk`. Signed with the debug key: fine for your own phones, not for the Play Store. |
| Windows | `flutter build windows --dart-define-from-file=.env.local` | `build\windows\x64\runner\Release\ink_frame.exe` |
| iPhone | `flutter run --release -d <iphone-id>` | installs on the connected iPhone. An `.ipa` for TestFlight needs distribution signing. |

## The pretend frame (`tools/ble_frame`)

The pretend frame stands in for a real Ink Frame over Bluetooth, until the firmware
exists. It shows the photo the frame would display.

Run it on one device and the Ink Frame app on another, because a device can't
connect to itself. For example, run the pretend frame on the Mac and the app on a
phone.

```sh
cd tools/ble_frame
flutter run -d macos                 # or: flutter run -d <android-id>
```

macOS asks for Bluetooth permission the first time.

**Connect it from the app:**

1. Open a frame you own.
2. Tap **Connect the frame**, then **Find the frame**.
3. Pick any network and tap **Connect**. Any password works, except `wrong`.

There's no pairing prompt with the default settings.

**What the window's controls do:**

| Control | What it does |
|---|---|
| **Check now** | The frame's green button, once connected: check for new photos, then show the newest one. |
| **Next photo** | The frame's white button: show the next photo. |
| **Pair again (hold 3 s)** | Click once. It does what holding the green button for 3 s does on the real frame: get ready to connect again. A frame that isn't connected yet is already ready when the window opens. |
| **Reset (hold 10 s)** | Click once. Forgets the frame, gets a new hardware ID, and gets ready to connect. Do this after the frame's photo storage was deleted. |
| **Model** | Shows the model it reports: the reTerminal E1002, the only one for now. |
| **Memory card** | Pretends an OK card, no card, or one it can't read, to see what the app says. |
| **Require pairing** | Off by default. On makes everything need an encrypted link, like the real frame. A Mac refuses an Android phone's pairing, so leave it off. |
| **Battery** slider | The battery level sent at the next check. To try the low-battery notification: set 15 %, press **Check now**, then **Account → Check batteries now** in the app. |

The pretend frame's log on the Mac:

```sh
tail -f ~/Library/Containers/com.psmyles.inkframe.bleFrame/Data/Library/Application\ Support/com.psmyles.inkframe.bleFrame/frame/log.txt
```

## The real frame (firmware, Phase 4a)

From `firmware/`, with the E1002 on USB-C and its power switch on:

```sh
pio run -t upload          # build and flash
pio device monitor         # its logs
```

Until Bluetooth (4b) it's set up over USB. See `firmware/README.md` for the console and
for linking it to a test album.

## Without Bluetooth: `frame_sim`

In developer mode, **Connect the frame → Connect with a code (developer)** shows a
command that includes a one-time token. Run it in `tools/frame_sim`. The app shows the
frame as connected once the simulator has claimed it.

```sh
cd tools/frame_sim
dart run bin/frame_sim.dart claim --ref <ref> --token <token>   # the command the app shows
dart run bin/frame_sim.dart sync                                # check for new photos (--battery 15 to report a low battery)
dart run bin/frame_sim.dart render                              # writes the photo it would show to .frame_sim/current.png
dart run bin/frame_sim.dart status
dart run bin/frame_sim.dart reset                               # forget the frame
```
