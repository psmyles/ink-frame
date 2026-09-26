/// Build-time configuration, set with `--dart-define` (see app/README.md).
/// Nothing here is secret: client IDs and page URLs are public by design.
abstract final class AppConfig {
  /// The central GitHub Pages site (`central/site/`).
  static const pagesUrl = String.fromEnvironment(
    'PAGES_URL',
    defaultValue: 'https://psmyles.github.io/ink-frame',
  );

  /// Google OAuth client IDs (PLAN.md §6.1). Empty = Google sign-in not offered.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleDesktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');

  /// Google treats a "Desktop app" client's secret as public (it ships in every
  /// installed app); its token endpoint still asks for it.
  static const googleDesktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  /// Sign in with Apple needs the App ID capability; off until it's registered.
  static const appleSignIn = bool.fromEnvironment('APPLE_SIGN_IN');

  /// Starts with developer mode on (it can also be turned on in Account).
  static const devMode = bool.fromEnvironment('DEV_MODE');
}
