# Ink Frame app

Flutter app for iOS, Android, Windows and macOS (Linux builds, untested). Screens and
flows follow [docs/app-flow.md](../docs/app-flow.md); the technical base is PLAN.md §8.

## Run

```sh
flutter run -d macos --dart-define=DEV_MODE=true                                    # Mac, iPhone, Android
flutter run -d windows --dart-define=DEV_MODE=true --dart-define-from-file=.env.local  # Windows/Linux (Google's desktop secret)
```

Run Flutter commands from this `app/` folder. `app/.env.local` (gitignored) holds
`GOOGLE_DESKTOP_CLIENT_SECRET=...` from the Desktop client's JSON.

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
| `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID` | Google sign-in on iOS/macOS and Android (web ID = server client ID). Default: ours (`shared/oauth-clients.json`) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | Google sign-in on Windows/Linux (browser + loopback). The ID defaults to ours; the secret comes from `.env.local` (Google treats it as public, but it stays out of git) |
| `APPLE_SIGN_IN` | Sign in with Apple on iOS/macOS; default `true` (team `48QFANT8RD`) |
| `PAGES_URL` | the `central/site` address (default `https://psmyles.github.io/ink-frame`) |
| `SUPABASE_OAUTH_CLIENT_ID` | the Supabase OAuth App for "Connect Supabase" in Set up a frame (default ours; its secret is only in the directory Worker) |
| `DIRECTORY_URL` | the directory (`central/directory/`) that finds your frames when you sign in on a new device; empty turns it off (then a link is needed) |

Sign-in buttons only appear for providers that are configured.

## Layout

- `lib/data/`: frame links, one Supabase client per frame (`FrameConnection`), the
  list of frames on this device (`FramesRepository`), models, errors.
- `lib/data/provisioner.dart`, `platform_api.dart`, `platform_auth.dart`,
  `backend_bundle.dart`: the setup wizard and owner tools: the Management API, "Connect
  Supabase" (OAuth through the directory Worker, or a token in dev mode) and the
  backend in `assets/backend/` (from `tools/dev/bundle-backend.ts`).
- `lib/auth/`: Google and Apple ID tokens.
- `lib/state/`: Riverpod providers. `lib/routing/`: go_router.
- `lib/features/<screen>/`, `lib/widgets/`, `lib/theme/`, `lib/l10n/` (all strings).
- The layout depends on window width only (`AdaptiveShell`, 900 px): a narrow
  desktop window is the phone layout.

## Tests

```sh
flutter test                                            # unit, widget, imaging (golden parity); no network
PHOTOS=<dir> flutter test test/imaging/png_bench_test.dart   # PNG size benchmark on real photos
deno run --allow-all ../tools/dev/app-live-test.ts      # against the dev project (needs no dev frame)
PREVIEW=1 flutter test test/preview --update-goldens    # renders screens to test/preview/out/ for a look
deno run --allow-all ../tools/dev/provision-live-test.ts  # the setup wizard's steps against the real Management API
```
