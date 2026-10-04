import 'frame_connection.dart';
import 'models.dart';

/// Settings, people, invites, your name, account and storage on one frame
/// (app-flow §4.3, §5, §7.2; shared/api/openapi.yaml). Reads go straight to the
/// tables under RLS; writes go through app-api.
class FrameApi {
  FrameApi(this.conn);

  final FrameConnection conn;

  /// `PATCH /frame/settings` with only the fields to change (owner).
  Future<Frame> updateSettings(Map<String, Object?> patch) async =>
      Frame.fromJson(await conn.callApi('PATCH', '/frame/settings', body: patch) as Map<String, dynamic>);

  /// `PATCH /frame` (owner).
  Future<Frame> rename(String name) async =>
      Frame.fromJson(await conn.callApi('PATCH', '/frame', body: {'name': name}) as Map<String, dynamic>);

  /// `PATCH /frame` with another panel model (owner): deletes every photo, which was
  /// made for the old panel, and disconnects the hardware (openapi.yaml). The caller
  /// has already asked.
  Future<Frame> changeModel(String modelId) async => Frame.fromJson(await conn.callApi('PATCH', '/frame',
      body: {'model_id': modelId, 'clear_photos': true}) as Map<String, dynamic>);

  /// A one-time token for connecting hardware (owner; 10 minutes).
  Future<PairingToken> createPairingToken() async =>
      PairingToken.fromJson(await conn.callApi('POST', '/pairing-tokens') as Map<String, dynamic>);

  /// A read-only token for this phone's battery checks (`POST /watch-tokens`).
  Future<String> createWatchToken() async =>
      ((await conn.callApi('POST', '/watch-tokens')) as Map<String, dynamic>)['watch_token'] as String;

  /// Disconnects the hardware (owner): it wipes itself at its next check.
  Future<void> disconnect() => conn.callApi('POST', '/frame/disconnect');

  /// Everyone on the frame, owner first, then by when they joined.
  Future<List<Member>> members() => conn.guard(() async {
        final rows = await conn.client.from('members').select('user_id, role, display_name, created_at').order('created_at');
        final list = [for (final r in rows) Member.fromJson(r)];
        return [...list.where((m) => m.isOwner), ...list.where((m) => !m.isOwner)];
      });

  /// Invites that can still be used (owner; RLS hides them from others).
  Future<List<Invite>> invites() => conn.guard(() async {
        final rows = await conn.client
            .from('invites')
            .select('id, expires_at, max_uses, uses')
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at', ascending: false);
        return [for (final r in rows) Invite.fromJson(r)].where((i) => i.uses < i.maxUses).toList();
      });

  Future<NewInvite> createInvite({int maxUses = 1, Duration expiresIn = const Duration(days: 7)}) async =>
      NewInvite.fromJson(await conn.callApi('POST', '/invites',
          body: {'max_uses': maxUses, 'expires_in_s': expiresIn.inSeconds}) as Map<String, dynamic>);

  Future<void> revokeInvite(String id) => conn.callApi('DELETE', '/invites/$id');

  /// The owner removes someone, or you leave (your own id).
  Future<void> removeMember(String userId) => conn.callApi('DELETE', '/members/$userId');

  /// Your display name on this frame.
  Future<void> updateMe(String displayName) => conn.callApi('PATCH', '/me', body: {'display_name': displayName});

  /// Leave and delete your account in this frame's project (not for the owner).
  Future<void> deleteMe({bool deletePhotos = false}) =>
      conn.callApi('DELETE', '/me${deletePhotos ? '?delete_photos=true' : ''}');

  Future<Usage> usage() async => Usage.fromJson(await conn.callApi('GET', '/usage') as Map<String, dynamic>);
}
