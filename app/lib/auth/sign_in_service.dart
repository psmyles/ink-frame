import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../config/app_config.dart';
import '../data/frame_connection.dart';

enum SignInMethod { google, apple, password }

/// Thrown when the person closes the sign-in sheet; the screen just stays put.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Gets an ID token from Google or Apple (PLAN.md §5.3, app-flow §7.1). The same
/// token then signs in to each frame's project.
class SignInService {
  static bool get _apple => Platform.isIOS || Platform.isMacOS;
  static bool get _desktopBrowser => Platform.isWindows || Platform.isLinux;

  /// What this build and platform offer, in display order.
  List<SignInMethod> methods({required bool devMode}) => [
        if (_googleConfigured) SignInMethod.google,
        if (AppConfig.appleSignIn && _apple) SignInMethod.apple,
        if (devMode) SignInMethod.password,
      ];

  bool get _googleConfigured => _desktopBrowser
      ? AppConfig.googleDesktopClientId.isNotEmpty
      : (_apple ? AppConfig.googleIosClientId.isNotEmpty : AppConfig.googleWebClientId.isNotEmpty);

  bool _googleReady = false;

  Future<IdTokenCredential> google() async {
    if (_desktopBrowser) return _googleLoopback();
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize(
        clientId: _apple ? AppConfig.googleIosClientId : null,
        serverClientId: AppConfig.googleWebClientId.isEmpty ? null : AppConfig.googleWebClientId,
      );
      _googleReady = true;
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('Google returned no ID token.');
      return IdTokenCredential(
        provider: OAuthProvider.google,
        idToken: idToken,
        name: account.displayName?.split(' ').first,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      rethrow;
    }
  }

  /// Windows/Linux: authorization code + PKCE in the system browser, redirected to
  /// a loopback port (Google "Desktop app" client).
  Future<IdTokenCredential> _googleLoopback() async {
    const redirect = 'http://localhost:53683';
    final verifier = _random(48);
    final state = _random(16);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': AppConfig.googleDesktopClientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    });
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: redirect,
        options: const FlutterWebAuth2Options(useWebview: false),
      );
    } on Exception catch (e) {
      if ('$e'.contains('CANCELED')) throw const SignInCancelled();
      rethrow;
    }
    final params = Uri.parse(result).queryParameters;
    if (params['state'] != state || params['code'] == null) throw const SignInCancelled();

    final res = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'code': params['code']!,
      'client_id': AppConfig.googleDesktopClientId,
      if (AppConfig.googleDesktopClientSecret.isNotEmpty) 'client_secret': AppConfig.googleDesktopClientSecret,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirect,
    });
    if (res.statusCode != 200) throw StateError('Google sign-in failed (${res.statusCode}).');
    final idToken = (jsonDecode(res.body) as Map<String, dynamic>)['id_token'] as String;
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(idToken.split('.')[1]))));
    return IdTokenCredential(
      provider: OAuthProvider.google,
      idToken: idToken,
      name: (claims as Map<String, dynamic>)['given_name'] as String?,
    );
  }

  Future<IdTokenCredential> apple() async {
    final nonce = _random(32);
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.fullName],
        nonce: sha256.convert(utf8.encode(nonce)).toString(),
      );
      final idToken = c.identityToken;
      if (idToken == null) throw StateError('Apple returned no ID token.');
      return IdTokenCredential(provider: OAuthProvider.apple, idToken: idToken, nonce: nonce, name: c.givenName);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) throw const SignInCancelled();
      rethrow;
    }
  }

  static String _random(int bytes) {
    final r = Random.secure();
    return base64Url.encode(List.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }
}
