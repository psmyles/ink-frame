/// An error from a frame's project: an app-api error (`{error: {code, message,
/// details}}`, shared/api/openapi.yaml), or one of the app's own codes below.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details});

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic>? details;

  /// The project is paused ("asleep because it wasn't used for a while"):
  /// Supabase answers HTTP 540 until the owner restores it.
  static const asleep = 'asleep';

  /// No answer at all (offline, DNS, timeout).
  static const offline = 'offline';

  /// Signed in, but not (or no longer) a member of this frame.
  static const notMember = 'not_member';

  /// The saved session is gone or was revoked; sign in again.
  static const signedOut = 'signed_out';

  /// Google/Apple/email sign-in to the frame's project was refused.
  static const signInFailed = 'sign_in_failed';

  bool get isAsleep => code == asleep;

  factory ApiException.fromResponse(int status, Object? body) {
    if (status == 540) return const ApiException(asleep, 'The frame is asleep.', status: 540);
    final error = body is Map<String, dynamic> ? body['error'] : null;
    if (error is Map<String, dynamic> && error['code'] is String) {
      return ApiException(
        error['code'] as String,
        error['message'] as String? ?? '',
        status: status,
        details: error['details'] as Map<String, dynamic>?,
      );
    }
    return ApiException('http_$status', 'Unexpected response ($status).', status: status);
  }

  @override
  String toString() => 'ApiException($code, $status): $message';
}
