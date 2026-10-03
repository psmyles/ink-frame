import 'dart:convert';

import 'api_error.dart';
import 'frame_connection.dart';
import 'frame_link.dart';
import 'models.dart';
import 'secure_store.dart';

/// The frames this device knows (their addresses), one [FrameConnection] each, and
/// the name last used when joining. Stored under `frames` and `profile`.
class FramesRepository {
  FramesRepository(this._store, {FrameConnection Function(FrameAddress, KeyValueStore)? connect})
      : _connect = connect ?? FrameConnection.new;

  final KeyValueStore _store;
  final FrameConnection Function(FrameAddress, KeyValueStore) _connect;
  final _connections = <FrameAddress, FrameConnection>{};
  final _restored = <FrameAddress, Future<bool>>{};

  Future<List<FrameAddress>> load() async {
    final raw = await _store.read('frames');
    if (raw == null) return [];
    return [for (final j in jsonDecode(raw) as List) FrameAddress.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> _save(List<FrameAddress> frames) =>
      _store.write('frames', jsonEncode([for (final f in frames) f.toJson()]));

  Future<void> add(FrameAddress address) async {
    final frames = await load();
    if (!frames.contains(address)) await _save([...frames, address]);
  }

  /// Forgets a frame on this device and signs out of it.
  Future<void> remove(FrameAddress address) async {
    await _save([for (final f in await load()) if (f != address) f]);
    await _store.delete('cache:${address.ref}');
    final c = _connections.remove(address);
    _restored.remove(address);
    if (c != null) {
      await c.signOut();
      await c.dispose();
    }
  }

  FrameConnection connection(FrameAddress address) =>
      _connections.putIfAbsent(address, () => _connect(address, _store));

  /// The connection with its saved session restored (once per run).
  Future<FrameConnection> ready(FrameAddress address) async {
    final c = connection(address);
    await _restored.putIfAbsent(address, c.restore);
    return c;
  }

  /// Signs in to a frame's project, without adding it to this device yet. Each
  /// sign-in gets a new connection (the previous one is closed), so nothing keeps
  /// using the session from before (FramesNotifier.signedIn refreshes the screens).
  Future<FrameConnection> signIn(FrameAddress address, Credential credential) async {
    final c = _connect(address, _store);
    try {
      await c.signIn(credential);
    } catch (_) {
      await c.dispose();
      rethrow;
    }
    final previous = _connections[address];
    _connections[address] = c;
    _restored[address] = Future.value(true);
    await previous?.dispose();
    return c;
  }

  /// Joins with an invite (already signed in): accept, remember the frame and the name.
  Future<Role> join(FrameAddress address, String code, String displayName) async {
    final role = await connection(address).acceptInvite(code, displayName);
    await add(address);
    await _store.write('profile', jsonEncode({'display_name': displayName}));
    return role;
  }

  /// Returning on a new device: sign in to each frame (from a link or the directory)
  /// and keep the ones you're still on. Returns the ones skipped because you're not.
  Future<List<FrameAddress>> signInAll(List<FrameAddress> frames, Credential credential) async {
    final skipped = <FrameAddress>[];
    for (final f in frames) {
      final c = await signIn(f, credential);
      try {
        await remember(f, await c.loadSummary());
        await add(f);
      } on ApiException catch (e) {
        if (e.code != ApiException.notMember) rethrow;
        skipped.add(f);
        await c.signOut();
      }
    }
    return skipped;
  }

  /// The name used when this person last joined a frame (app-flow §1.2 step 3).
  Future<String?> lastDisplayName() async {
    final raw = await _store.read('profile');
    return raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>)['display_name'] as String?;
  }

  /// Remembers the name you go by (Account → Your name), for the next frame you join.
  Future<void> setDisplayName(String name) => _store.write('profile', jsonEncode({'display_name': name}));

  /// Last known name, owner and role, so Home can say which frame is asleep or
  /// offline when it can't be read. Stored under `cache:<ref>`.
  Future<CachedFrame?> cached(FrameAddress address) async {
    final raw = await _store.read('cache:${address.ref}');
    return raw == null ? null : CachedFrame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> remember(FrameAddress address, FrameSummary s) => _store.write(
        'cache:${address.ref}',
        jsonEncode(CachedFrame(s.frame.name, s.owner.displayName, s.isMine).toJson()),
      );

  Future<void> signOutAll() async {
    for (final f in await load()) {
      await remove(f);
    }
  }
}

class CachedFrame {
  const CachedFrame(this.name, this.ownerName, this.isMine);

  final String name;
  final String ownerName;
  final bool isMine;

  Map<String, Object> toJson() => {'name': name, 'owner_name': ownerName, 'is_mine': isMine};
  factory CachedFrame.fromJson(Map<String, dynamic> j) =>
      CachedFrame(j['name'] as String, j['owner_name'] as String, j['is_mine'] as bool);
}
