import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_error.dart';
import 'frame_link.dart';
import 'models.dart';
import 'secure_store.dart';

/// What the user signs in with. The same credential signs them in to every frame
/// they join in one go (each frame is its own Supabase project and auth user).
sealed class Credential {
  const Credential();
}

/// A Google or Apple ID token from the platform sheet or browser flow (PLAN.md §5.3).
class IdTokenCredential extends Credential {
  const IdTokenCredential({required this.provider, required this.idToken, this.accessToken, this.nonce, this.name});

  final OAuthProvider provider;
  final String idToken;
  final String? accessToken;

  /// The raw nonce whose sha256 went to the provider (Apple).
  final String? nonce;

  /// A first name suggestion for "What should the others see?".
  final String? name;
}

/// Email and password: dev mode on dev projects only (app-flow §7.1).
class PasswordCredential extends Credential {
  const PasswordCredential(this.email, this.password);

  final String email;
  final String password;
}

/// One frame = one Supabase project, with its own client and session. The session
/// is kept in secure storage under `session:<ref>`.
class FrameConnection {
  FrameConnection(this.address, this._store, {http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        client = SupabaseClient(
          address.url,
          address.key,
          httpClient: httpClient,
          // ID-token and password sign-in never redirect, so PKCE storage isn't needed.
          authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
        ) {
    _authSub = client.auth.onAuthStateChange.listen(_persist, onError: (_) {});
  }

  final FrameAddress address;
  final SupabaseClient client;
  final KeyValueStore _store;
  final http.Client _http;
  late final StreamSubscription<AuthState> _authSub;

  String get _sessionKey => 'session:${address.ref}';
  bool get isSignedIn => client.auth.currentSession != null;
  String? get userId => client.auth.currentUser?.id;

  Future<void> _persist(AuthState state) async {
    final session = state.session;
    if (state.event == AuthChangeEvent.signedOut) {
      await _store.delete(_sessionKey);
    } else if (session != null) {
      await _store.write(_sessionKey, jsonEncode(session.toJson()));
    }
  }

  /// Restores the saved session (refreshing it if expired). Returns whether signed in.
  /// Throws [ApiException] (`offline`, `asleep`) when the refresh can't get an
  /// answer; the saved session is kept for the next try.
  Future<bool> restore() async {
    final saved = await _store.read(_sessionKey);
    if (saved == null) return false;
    try {
      await client.auth.recoverSession(saved);
      return true;
    } on AuthRetryableFetchException catch (e) {
      throw _retryable(e);
    } on AuthException {
      await _store.delete(_sessionKey);
      return false;
    } on SocketException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    }
  }

  /// No answer, or a 5xx such as 540 (asleep): auth keeps the session for these.
  static ApiException _retryable(AuthRetryableFetchException e) => e.statusCode == '540'
      ? ApiException.fromResponse(540, null)
      : ApiException(ApiException.offline, e.message);

  /// Whether this frame's project was deleted (by its owner, from Supabase).
  /// Supabase answers HTTP 410 for a while; after that the address stops existing
  /// while Supabase itself still answers. Offline or slow counts as not gone.
  Future<bool> isGone() async {
    const limit = Duration(seconds: 15);
    try {
      final res = await _http.get(Uri.parse('${address.url}/auth/v1/health'), headers: {'apikey': address.key}).timeout(limit);
      return res.statusCode == 410;
    } on Exception catch (e) {
      if (!e.toString().contains('Failed host lookup')) return false;
    }
    try {
      await _http.head(Uri.parse('https://api.supabase.com/')).timeout(limit);
      return true;
    } on Exception {
      return false;
    }
  }

  /// Signs in to this frame's project. Throws [ApiException] (`sign_in_failed`,
  /// `asleep`, `offline`).
  Future<void> signIn(Credential credential) => guard(authCode: ApiException.signInFailed, () async {
        switch (credential) {
          case IdTokenCredential c:
            await client.auth.signInWithIdToken(
              provider: c.provider,
              idToken: c.idToken,
              accessToken: c.accessToken,
              nonce: c.nonce,
            );
          case PasswordCredential c:
            try {
              await client.auth.signInWithPassword(email: c.email, password: c.password);
            } on AuthException catch (e) {
              if (e.code != 'invalid_credentials') rethrow;
              // Dev projects confirm sign-ups automatically (tools/dev/provision.ts).
              final r = await client.auth.signUp(email: c.email, password: c.password);
              // An existing email with the wrong password "signs up" without a session.
              if (r.session == null) rethrow;
            }
        }
      });

  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {
      // Offline or asleep: the local session is cleared either way.
    }
    await _store.delete(_sessionKey);
  }

  /// The frame, you and its owner, read directly under RLS.
  Future<FrameSummary> loadSummary() => guard(() async {
        final me = userId;
        if (me == null) throw const ApiException(ApiException.signedOut, 'Not signed in.');
        final frameRow = await client.from('frame').select().maybeSingle();
        final memberRows = await client.from('members').select('user_id, role, display_name');
        final members = [for (final r in memberRows) Member.fromJson(r)];
        final mine = members.where((m) => m.userId == me);
        if (frameRow == null || mine.isEmpty) {
          throw const ApiException(ApiException.notMember, 'You are not on this frame.');
        }
        return FrameSummary(
          frame: Frame.fromJson(frameRow),
          me: mine.single,
          owner: members.firstWhere((m) => m.role == Role.owner),
        );
      });

  /// `POST /invites/accept`. Returns your role.
  Future<Role> acceptInvite(String code, String displayName) async {
    final r = await callApi('POST', '/invites/accept', body: {'code': code, 'display_name': displayName});
    return Role.values.byName((r as Map<String, dynamic>)['role'] as String);
  }

  /// Calls app-api with your session. Throws [ApiException].
  Future<Object?> callApi(String method, String path, {Object? body}) => guard(() async {
        final token = client.auth.currentSession?.accessToken;
        if (token == null) throw const ApiException(ApiException.signedOut, 'Not signed in.');
        final req = http.Request(method, Uri.parse('${address.url}/functions/v1/app-api$path'))
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'apikey': address.key,
            if (body != null) 'Content-Type': 'application/json',
          });
        if (body != null) req.body = jsonEncode(body);
        final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
        final decoded = res.body.isEmpty ? null : _tryJson(res.body);
        if (res.statusCode >= 400) throw ApiException.fromResponse(res.statusCode, decoded);
        return decoded;
      });

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  /// Runs [body], mapping transport, PostgREST and auth failures to [ApiException].
  Future<T> guard<T>(Future<T> Function() body, {String authCode = ApiException.signedOut}) async {
    try {
      return await body();
    } on ApiException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '540' || e.code == '410') throw ApiException.fromResponse(int.parse(e.code!), null);
      if (e.code == 'PGRST301' || e.code == 'PGRST303' || e.code == '401') {
        throw ApiException(ApiException.signedOut, e.message);
      }
      throw ApiException(e.code ?? 'postgrest', e.message);
    } on AuthRetryableFetchException catch (e) {
      throw _retryable(e);
    } on AuthException catch (e) {
      if (e.statusCode == '540') throw ApiException.fromResponse(540, null);
      throw ApiException(authCode, e.message);
    } on SocketException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on http.ClientException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on TimeoutException {
      throw const ApiException(ApiException.offline, 'Timed out.');
    }
  }

  Future<void> dispose() async {
    await _authSub.cancel();
    await client.dispose();
  }
}
