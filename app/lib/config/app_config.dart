/// Build-time configuration, set with `--dart-define` (see app/README.md).
/// Nothing here is secret: client IDs and page URLs are public by design.
abstract final class AppConfig {
  /// The central GitHub Pages site (`central/site/`).
  static const pagesUrl = String.fromEnvironment(
    'PAGES_URL',
    defaultValue: 'https://psmyles.github.io/ink-frame',
  );

  /// The directory (`central/directory/`): finds your frames when you sign in on a
  /// new device. Empty = off (signing in on a new device then needs a link).
  static const directoryUrl = String.fromEnvironment(
    'DIRECTORY_URL',
    defaultValue: 'https://ink-frame-directory.psmyles.workers.dev',
  );

  /// The Supabase OAuth App "Ink Frame" (`shared/oauth-clients.json`), for "Connect
  /// Supabase" in the setup wizard. Its secret stays in the directory Worker.
  static const supabaseOAuthClientId = String.fromEnvironment(
    'SUPABASE_OAUTH_CLIENT_ID',
    defaultValue: '35affcb4-826f-4c9b-abdd-00187b5efc45',
  );

  /// Google OAuth client IDs (PLAN.md §6.1), Google Cloud project `ink-frame-510506`,
  /// for the bundle/package ID `com.psmyles.inkframe`. Public by design; a fork with
  /// its own IDs overrides them with --dart-define. Empty = Google not offered.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '754064113071-qhj80g401b1gbpsip8c3pharcsc0sk4b.apps.googleusercontent.com',
  );
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '754064113071-tv7te223egk52cpplv9glhkf5p09kopq.apps.googleusercontent.com',
  );
  static const googleDesktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '754064113071-rngfenpv03v146te0j1ng7osv0og7tv8.apps.googleusercontent.com',
  );

  /// Google treats a "Desktop app" client's secret as public (it ships in every
  /// installed app); its token endpoint still asks for it. Kept out of git anyway:
  /// `--dart-define-from-file=.env.local` (app/README.md).
  static const googleDesktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  /// Sign in with Apple (iOS/macOS; the App ID has the capability, team 48QFANT8RD).
  static const appleSignIn = bool.fromEnvironment('APPLE_SIGN_IN', defaultValue: true);

  /// Starts with developer mode on (it can also be turned on in Account).
  static const devMode = bool.fromEnvironment('DEV_MODE');
}
