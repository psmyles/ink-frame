# Ink Frame app

Flutter app for iOS, Android, Windows and macOS (Linux builds, untested). Screens and
flows follow [docs/app-flow.md](../docs/app-flow.md); the technical base is PLAN.md §8.

## Run

```sh
flutter run -d macos --dart-define=DEV_MODE=true      # or -d windows, or a phone
```

Developer mode (also: Account → tap the version 7 times) adds email/password
sign-in, which works on dev projects only. To get a frame to join on the dev project:

```sh
deno run --allow-read --allow-net --allow-env ../tools/dev/dev-frame.ts            # prints an invite link
deno run --allow-read --allow-net --allow-env ../tools/dev/dev-frame.ts --remove   # before running the backend tests
```

Then in the app: **I've been invited** → paste the link → sign in with any email and
password (a new dev user is created) → your name.

## Build configuration (`--dart-define`)

| Name | Use |
|---|---|
| `DEV_MODE` | start with developer mode on |
| `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID` | Google sign-in on iOS/macOS and Android (web ID = server client ID) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | Google sign-in on Windows/Linux (browser + loopback). Google treats a Desktop client's secret as public |
| `APPLE_SIGN_IN` | `true` once the App ID has Sign in with Apple |
| `PAGES_URL` | the `central/site` address (default `https://psmyles.github.io/ink-frame`) |

Sign-in buttons only appear for providers that are configured.

## Layout

- `lib/data/`: frame links, one Supabase client per frame (`FrameConnection`), the
  list of frames on this device (`FramesRepository`), models, errors.
- `lib/auth/`: Google and Apple ID tokens.
- `lib/state/`: Riverpod providers. `lib/routing/`: go_router.
- `lib/features/<screen>/`, `lib/widgets/`, `lib/theme/`, `lib/l10n/` (all strings).
- The layout depends on window width only (`AdaptiveShell`, 900 px): a narrow
  desktop window is the phone layout.

## Tests

```sh
flutter test test/unit test/widget                      # no network
deno run --allow-all ../tools/dev/app-live-test.ts      # against the dev project (needs no dev frame)
PREVIEW=1 flutter test test/preview --update-goldens    # renders screens to test/preview/out/ for a look
```
