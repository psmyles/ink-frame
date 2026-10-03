import 'dart:convert';
import 'dart:math';

import 'backend_bundle.dart';
import 'frame_link.dart';
import 'platform_api.dart';

/// Sets up, updates, wakes and deletes frames' projects through the Management API
/// (PLAN.md §6.2–6.4). Every step can run again safely, so the wizard can save its
/// progress after each one and resume after a failure or a closed app.
/// `tools/dev/provision.ts` is the reference.
class Provisioner {
  Provisioner(
    this.api,
    this.bundle, {
    this.pollEvery = const Duration(seconds: 3),
    this.readyTimeout = const Duration(minutes: 10),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final PlatformApi api;
  final BackendBundle bundle;
  final Duration pollEvery;
  final Duration readyTimeout;
  final Future<void> Function(Duration) _sleep;

  /// Creates the frame's project in the account's (OAuth: the chosen) organization, in
  /// the region nearest [timezone]. Returns its ref. Throws `project_limit` when the
  /// free plan's 2 projects are used.
  Future<String> createProject({required String frameName, required String timezone}) async {
    final orgs = await api.organizations();
    if (orgs.isEmpty) throw const PlatformApiException('no_org', 'This Supabase account has no organization.');
    final r = Random.secure();
    return api.createProject(
      name: projectName(frameName),
      org: orgs.first.slug,
      // Never needed again: everything goes through the Management API.
      dbPass: base64Url.encode(List.generate(24, (_) => r.nextInt(256))),
      region: regionFor(timezone),
    );
  }

  /// "Ink Frame - Kitchen", as the owner sees it in their Supabase dashboard.
  static String projectName(String frameName) {
    final plain = frameName.replaceAll(RegExp(r'[^A-Za-z0-9 \-]'), '').trim();
    return plain.isEmpty ? 'Ink Frame' : 'Ink Frame - ${plain.length > 40 ? plain.substring(0, 40) : plain}';
  }

  /// Supabase's region group for a time zone (PLAN.md §6.2: not asked).
  static String regionFor(String timezone) {
    final area = timezone.split('/').first;
    return switch (area) {
      'America' || 'US' || 'Canada' => 'americas',
      'Asia' || 'Australia' || 'Pacific' || 'Indian' => 'apac',
      _ => 'emea',
    };
  }

  /// Waits until the project and the services a frame needs are up (~4 s when new,
  /// ~3 min after waking).
  Future<void> waitUntilReady(String ref) async {
    final deadline = DateTime.now().add(readyTimeout);
    while (true) {
      if (await api.status(ref) == 'ACTIVE_HEALTHY' && await _healthy(ref)) return;
      if (DateTime.now().isAfter(deadline)) {
        throw const PlatformApiException('not_ready', "The frame's storage didn't start in time.");
      }
      await _sleep(pollEvery);
    }
  }

  Future<bool> _healthy(String ref) async {
    try {
      return await api.healthy(ref);
    } on PlatformApiException catch (e) {
      if (e.code == PlatformApiException.offline || e.code == PlatformApiException.reconnect) rethrow;
      return false; // health isn't answered while the project starts
    }
  }

  /// The frame's schema version (0 before the first migration).
  Future<int> schemaVersion(String ref) async {
    final exists = (await api.sql(ref, "select to_regclass('public.schema_version') is not null as exists")).first['exists'] == true;
    if (!exists) return 0;
    return ((await api.sql(ref, 'select coalesce(max(version), 0) as v from public.schema_version')).first['v'] as num).toInt();
  }

  /// Applies the pending migrations (each in one transaction with its schema_version
  /// row), then the seed and the project's URL (like tools/dev/migrate.ts).
  Future<void> installDatabase(String ref) async {
    final current = await schemaVersion(ref);
    for (final m in bundle.migrations.where((m) => m.version > current)) {
      await api.sql(ref, 'begin;\n${m.sql}\n;insert into public.schema_version (version) values (${m.version});\ncommit;');
    }
    await api.sql(ref, bundle.seed);
    await api.sql(ref, "insert into private.config (key, value) values ('project_url', 'https://$ref.supabase.co') "
        'on conflict (key) do update set value = excluded.value');
  }

  /// Deploys the functions, then records which backend the frame now runs.
  Future<void> deployFunctions(String ref) async {
    for (final e in bundle.functions.entries) {
      await api.deployFunction(ref, e.key, e.value);
    }
    await api.sql(ref, "insert into private.config (key, value) values ('backend', ${_q(bundle.fingerprint)}) "
        'on conflict (key) do update set value = excluded.value');
  }

  /// Whether this app has a newer backend than the frame's: a later schema, or the
  /// same schema with different functions. Never offers to go back to an older schema.
  Future<bool> updateAvailable(String ref) async {
    final v = await schemaVersion(ref);
    if (v != bundle.latestVersion) return v < bundle.latestVersion;
    final rows = await api.sql(ref, "select value from private.config where key = 'backend'");
    return rows.isEmpty || rows.first['value'] != bundle.fingerprint;
  }

  /// Google/Apple sign-in; email sign-in only for developer setups ([keepEmail]: dev
  /// mode with a personal access token, so developer sign-in works there).
  Future<void> configureSignIn(String ref, {bool keepEmail = false}) => api.configureAuth(ref, {
        ...bundle.auth,
        if (keepEmail) 'mailer_autoconfirm': true else 'external_email_enabled': false,
      });

  /// The frame's name, model and time zone (once).
  Future<void> describeFrame(String ref, {required String name, required String modelId, required String timezone}) async {
    final n = ((await api.sql(ref, 'select count(*)::int as n from public.frame')).first['n'] as num).toInt();
    if (n > 0) return;
    await api.sql(ref, 'select private.setup_frame(${_q(name)}, ${_q(modelId)}, ${_q(timezone)})');
  }

  Future<FrameAddress> address(String ref) async => FrameAddress('https://$ref.supabase.co', await api.publishableKey(ref));

  /// Makes [userId] (signed in to the new project) its owner, once.
  Future<void> setOwner(String ref, {required String userId, required String displayName}) async {
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(userId)) throw ArgumentError.value(userId, 'userId');
    final owners = await api.sql(ref, "select user_id from public.members where role = 'owner'");
    if (owners.isNotEmpty) {
      if (owners.first['user_id'] == userId) return;
      throw const PlatformApiException('owner_exists', 'This frame already has an owner.');
    }
    await api.sql(ref, "select private.set_owner('$userId', ${_q(displayName)})");
  }

  /// "Update": brings a frame's database and functions up to this app's backend.
  Future<void> update(String ref) async {
    await installDatabase(ref);
    await deployFunctions(ref);
  }

  /// "Wake up" a paused frame (PLAN.md §6.4).
  Future<void> wakeUp(String ref) async {
    if (await api.status(ref) != 'ACTIVE_HEALTHY') await api.restore(ref);
    await waitUntilReady(ref);
  }

  Future<void> deleteFrame(String ref) => api.deleteProject(ref);

  static String _q(String v) => "'${v.replaceAll("'", "''")}'";
}
