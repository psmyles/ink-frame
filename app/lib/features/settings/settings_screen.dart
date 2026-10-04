import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../battery/battery_watch.dart';
import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../data/timezones.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../state/setup.dart';
import '../../widgets/formatting.dart';
import '../../widgets/side_panel.dart';
import '../../widgets/text_prompt.dart';
import '../connect/connect_frame_screen.dart';
import '../storage/storage_screen.dart';
import 'owner_tools.dart';

/// Frame settings (app-flow §4.3): the owner edits, everyone else reads. Each change
/// saves straight away.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.address});

  final FrameAddress address;

  /// 1 h–2 days (PLAN.md §15), for both intervals.
  static const intervals = [3600, 7200, 14400, 28800, 43200, 86400, 172800];

  /// null = off.
  static const batteryLevels = <int?>[null, 10, 20, 30];

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Values being saved, shown instead of the frame's until the save finishes.
  final _pending = <String, Object?>{};

  FrameAddress get _a => widget.address;

  T _v<T>(String key, T current) => _pending.containsKey(key) ? _pending[key] as T : current;

  Future<void> _save(Map<String, Object?> patch, {bool reachesFrame = true}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending.addAll(patch));
    try {
      final api = ref.read(frameApiProvider(_a));
      if (patch.containsKey('name')) {
        await api.rename(patch['name']! as String);
      } else {
        await api.updateSettings(patch);
      }
      ref.invalidate(frameViewProvider(_a));
      await ref.read(frameViewProvider(_a).future);
      messenger.showSnackBar(SnackBar(content: Text(reachesFrame ? l.savedNextCheck : l.saved)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l.couldntSave)));
    } finally {
      if (mounted) setState(() => patch.keys.forEach(_pending.remove));
    }
  }

  /// Null when dismissed; otherwise the choice (whose value may itself be null: "Off").
  Future<_Choice<T>?> _pick<T>(String title, List<T> options, T current, String Function(T) label) =>
      showDialog<_Choice<T>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final o in options)
              ListTile(
                title: Text(label(o)),
                trailing: o == current ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                onTap: () => Navigator.pop(context, _Choice(o)),
              ),
          ],
        ),
      );

  Future<void> _rename(String current) async {
    final l = AppLocalizations.of(context);
    final name = await promptText(context, title: l.renameTitle, initial: current, label: l.albumName);
    if (name != null) await _save({'name': name}, reachesFrame: false);
  }

  /// Another panel model (owner): clears the photos, so it asks first (app-flow §4.3).
  Future<void> _changeModel(FrameSummary s, String currentName) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final models = (await ref.read(backendBundleProvider.future)).models;
    String nameOf(String id) => models.where((m) => m.id == id).firstOrNull?.name ?? id;
    final picked = await _pick(l.setupModelTitle, [for (final m in models) m.id], s.frame.modelId, nameOf);
    if (picked == null || picked.value == s.frame.modelId || !mounted) return;
    final count = ref.read(usageProvider(_a)).value?.frame.images ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.changeModelConfirm(count, s.frame.name, nameOf(picked.value), currentName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.switchModel)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(frameApiProvider(_a)).changeModel(picked.value);
      ref.invalidate(frameViewProvider(_a));
      ref.invalidate(photosProvider(_a));
      messenger.showSnackBar(SnackBar(content: Text(l.savedNextCheck)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l.couldntSave)));
    }
  }

  /// The hardware wipes itself at its next check; the photos stay (openapi.yaml).
  Future<void> _disconnect(String name) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.disconnectConfirm(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.disconnectFrame)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(frameApiProvider(_a)).disconnect();
      ref.invalidate(frameViewProvider(_a));
      messenger.showSnackBar(SnackBar(content: Text(l.disconnected)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l.couldntSave)));
    }
  }

  Future<void> _pickTime(String key, String current) async {
    final t = await showTimePicker(context: context, initialTime: parseHhmm(current));
    if (t != null && toHhmm(t) != current) await _save({key: toHhmm(t)});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = ref.watch(frameViewProvider(_a)).value?.summary;

    return Scaffold(
      appBar: PanelAppBar(title: l.settings),
      body: summary == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, l, theme, summary),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, ThemeData theme, FrameSummary s) {
    final f = s.frame;
    final owner = s.isMine;
    final model = ref.watch(frameModelProvider(_a)).value?.model.name ?? f.modelId;
    final usage = ref.watch(usageProvider(_a)).value;
    final locale = Localizations.localeOf(context);

    final name = _v('name', f.name);
    final imageInterval = _v('image_interval_s', f.imageIntervalS);
    final order = _v('display_order', f.displayOrder);
    final quietStart = _v('quiet_start', f.quietStart);
    final quietEnd = _v('quiet_end', f.quietEnd);
    final quietOn = quietStart != null && quietEnd != null;
    final syncInterval = _v('sync_interval_s', f.syncIntervalS);
    final timezone = _v('timezone', f.timezone);
    final battery = _v('low_battery_pct', f.lowBatteryPct);
    String batteryLabel(int? v) => v == null ? l.off : l.percent(v);
    final (city, region) = timeZoneParts(timezone);
    // "Frame F7C4" (what its setup screen shows), then its software and battery.
    final suffix = f.hwSuffix;
    final hardwareDetails = [
      if (f.connected && suffix != null) f.fwVersion == null ? l.hardwareConnectedNoVersion : l.hardwareConnected(f.fwVersion!),
      if (f.batteryPct != null) l.batteryNow(f.batteryPct!),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!owner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.onlyOwnerChanges(s.owner.displayName), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        // The album (photos, people, storage), then the frame on the wall (PLAN.md §2).
        _Section(l.sectionAlbum),
        ListTile(
          title: Text(l.albumName),
          subtitle: Text(name),
          trailing: owner ? const Icon(Icons.edit_outlined) : null,
          onTap: owner ? () => _rename(name) : null,
        ),
        ListTile(
          title: Text(l.storage),
          subtitle: usage == null
              ? null
              : Text(l.storageUsed(formatBytes(usage.frame.bytes, locale), formatBytes(usage.limitBytes, locale))),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openPanel<void>(context, (_) => StorageScreen(address: _a)),
        ),
        _Section(l.sectionHardware),
        ListTile(
          title: Text(!f.connected
              ? l.hardwareNotConnected
              : suffix != null
                  ? l.frameNamed(suffix)
                  : (f.fwVersion == null ? l.hardwareConnectedNoVersion : l.hardwareConnected(f.fwVersion!))),
          subtitle: hardwareDetails.isEmpty ? null : Text(hardwareDetails.join(' · ')),
          leading: Icon(f.connected ? Icons.check_circle_outline : Icons.link_off),
        ),
        if (f.connected && f.sdTotalBytes != null) _CardTile(frame: f, photoBytes: usage?.frame.bytes),
        ListTile(
          title: Text(l.frameModel),
          subtitle: Text(model),
          // Nothing to change to while there's one model (shared/presets.json).
          trailing: owner && (ref.watch(backendBundleProvider).value?.models.length ?? 0) > 1
              ? TextButton(onPressed: () => _changeModel(s, model), child: Text(l.changeModel))
              : null,
        ),
        if (owner)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 8, children: [
              if (f.connected) ...[
                TextButton(onPressed: () => openConnectFrame(context, _a), child: Text(l.connectDifferentFrame)),
                TextButton(onPressed: () => _disconnect(name), child: Text(l.disconnectFrame)),
              ] else
                FilledButton.tonal(onPressed: () => openConnectFrame(context, _a), child: Text(l.connectFrame)),
            ]),
          ),
        _Section(l.sectionPhotos),
        ListTile(
          title: Text(l.changePhotoEvery),
          subtitle: Text(formatInterval(l, imageInterval)),
          onTap: owner
              ? () async {
                  final c = await _pick(l.changePhotoEvery, SettingsScreen.intervals, imageInterval, (s) => formatInterval(l, s));
                  if (c != null && c.value != imageInterval) await _save({'image_interval_s': c.value});
                }
              : null,
        ),
        if (owner) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            // Large text: the buttons go under the label.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
              Text(l.order, style: theme.textTheme.bodyLarge),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'random', label: Text(l.orderShuffle)),
                  ButtonSegment(value: 'sequential', label: Text(l.orderInOrder)),
                ],
                selected: {order},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _save({'display_order': v.single}),
              ),
            ],
            ),
          ),
          SwitchListTile(
            title: Text(l.quietHours),
            subtitle: Text(l.quietHoursHint),
            value: quietOn,
            onChanged: (on) =>
                _save(on ? {'quiet_start': '22:00', 'quiet_end': '07:00'} : {'quiet_start': null, 'quiet_end': null}),
          ),
          if (quietOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                  child: _TimeButton(
                    label: l.quietFrom,
                    value: formatHhmm(context, quietStart),
                    onTap: () => _pickTime('quiet_start', quietStart),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeButton(
                    label: l.quietTo,
                    value: formatHhmm(context, quietEnd),
                    onTap: () => _pickTime('quiet_end', quietEnd),
                  ),
                ),
              ]),
            ),
        ] else ...[
          // Read-only: plain values (greyed-out controls hide which option is set).
          ListTile(title: Text(l.order), subtitle: Text(order == 'sequential' ? l.orderInOrder : l.orderShuffle)),
          ListTile(
            title: Text(l.quietHours),
            subtitle: Text(quietOn ? '${formatHhmm(context, quietStart)} – ${formatHhmm(context, quietEnd)}' : l.off),
          ),
        ],
        _Section(l.sectionChecking),
        ListTile(
          title: Text(l.checkForNewPhotos),
          subtitle: Text('${formatInterval(l, syncInterval)} · ${l.checkMoreOftenHint}'),
          onTap: owner
              ? () async {
                  final c = await _pick(l.checkForNewPhotos, SettingsScreen.intervals, syncInterval, (s) => formatInterval(l, s));
                  if (c != null && c.value != syncInterval) await _save({'sync_interval_s': c.value});
                }
              : null,
        ),
        ListTile(
          title: Text(l.timeZone),
          subtitle: Text(region.isEmpty ? city : '$city · $region'),
          onTap: owner
              ? () async {
                  final v = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => TimeZonePicker(current: timezone)),
                  );
                  if (v != null && v != timezone) await _save({'timezone': v});
                }
              : null,
        ),
        _Section(l.sectionBattery),
        ListTile(
          title: Text(l.lowBatteryWarning),
          subtitle: Text('${batteryLabel(battery)} · ${l.lowBatteryHint}'),
          onTap: owner
              ? () async {
                  final c = await _pick(l.lowBatteryWarning, SettingsScreen.batteryLevels, battery, batteryLabel);
                  if (c != null && c.value != battery) await _save({'low_battery_pct': c.value}, reachesFrame: false);
                }
              : null,
        ),
        if (ref.watch(batteryWatchProvider).supported) _NotifyTile(address: _a, summary: s, warningOn: battery != null),
        if (owner) ...[
          _Section(l.sectionOwner),
          OwnerTools(address: _a, frameName: name),
        ],
      ],
    );
  }
}

/// "Notify me when it's low" on this phone (PLAN.md §15): each person chooses; on by
/// default for the owner.
class _NotifyTile extends ConsumerStatefulWidget {
  const _NotifyTile({required this.address, required this.summary, required this.warningOn});

  final FrameAddress address;
  final FrameSummary summary;
  final bool warningOn;

  @override
  ConsumerState<_NotifyTile> createState() => _NotifyTileState();
}

class _NotifyTileState extends ConsumerState<_NotifyTile> {
  bool? _on;
  var _available = true;
  var _allowed = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final watch = ref.read(batteryWatchProvider);
    final choice = await watch.choice(widget.address);
    final available = await watch.available(widget.address);
    final allowed = await ref.read(notificationsProvider).allowed();
    if (!mounted) return;
    setState(() {
      _on = BatteryWatch.wanted(choice, isOwner: widget.summary.isMine);
      _available = available;
      _allowed = allowed;
    });
  }

  Future<void> _set(bool on) async {
    setState(() {
      _busy = true;
      _on = on;
    });
    try {
      if (on) await ref.read(notificationsProvider).request();
      await ref.read(batteryWatchProvider).choose(widget.address, on, ref.read(frameApiProvider(widget.address)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).couldntSave)));
    }
    await _read();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final on = _on;
    final String hint;
    if (!widget.warningOn) {
      hint = l.notifyWarningOff;
    } else if (!_available) {
      hint = widget.summary.isMine ? l.notifyNeedsUpdateOwner : l.notifyNeedsUpdate(widget.summary.owner.displayName);
    } else if (on == true && !_allowed) {
      hint = l.notifyBlocked;
    } else {
      hint = l.notifyLowBatteryHint;
    }
    return SwitchListTile(
      title: Text(l.notifyLowBattery),
      subtitle: Text(hint),
      value: (on ?? false) && widget.warningOn && _available,
      onChanged: on == null || _busy || !widget.warningOn || !_available ? null : _set,
    );
  }
}

/// A picked option, so "Off" (null) differs from closing the dialog.
class _Choice<T> {
  const _Choice(this.value);
  final T value;
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.value, this.onTap});

  final String label, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}

/// Searchable time zone list; returns the IANA name.
class TimeZonePicker extends StatefulWidget {
  const TimeZonePicker({super.key, required this.current});

  final String current;

  @override
  State<TimeZonePicker> createState() => _TimeZonePickerState();
}

class _TimeZonePickerState extends State<TimeZonePicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final zones = q.isEmpty ? timeZones : timeZones.where((z) => z.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: l.searchTimeZones, border: InputBorder.none),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: ListView.builder(
        itemCount: zones.length,
        itemBuilder: (context, i) {
          final (city, region) = timeZoneParts(zones[i]);
          return ListTile(
            title: Text(city),
            subtitle: region.isEmpty ? null : Text(region),
            trailing: zones[i] == widget.current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, zones[i]),
          );
        },
      ),
    );
  }
}

/// The frame's memory card at its last check: size, use, and whether the photos fit.
class _CardTile extends StatelessWidget {
  const _CardTile({required this.frame, required this.photoBytes});

  final Frame frame;
  final int? photoBytes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    if (frame.noCard) {
      return ListTile(
        leading: Icon(Icons.sd_card_alert_outlined, color: theme.colorScheme.error),
        title: Text(l.memoryCard),
        subtitle: Text(l.cardMissing),
      );
    }
    final total = frame.sdTotalBytes!;
    final used = total - (frame.sdFreeBytes ?? total);
    final short = photoBytes == null ? 0 : frame.cardShortBy(photoBytes!);
    return ListTile(
      leading: const Icon(Icons.sd_card_outlined),
      title: Text(l.memoryCard),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.cardUsage(formatBytes(used, locale), formatBytes(total, locale), formatBytes(frame.cacheBytes ?? 0, locale))),
        if (short > 0)
          Text(l.cardTooSmall(frame.name, formatBytes(short, locale)), style: TextStyle(color: theme.colorScheme.error)),
      ]),
    );
  }
}
