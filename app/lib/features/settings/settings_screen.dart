import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../data/timezones.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../widgets/formatting.dart';
import '../../widgets/side_panel.dart';
import '../../widgets/text_prompt.dart';
import '../storage/storage_screen.dart';

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
    final name = await promptText(context, title: l.renameTitle, initial: current, label: l.frameName);
    if (name != null) await _save({'name': name}, reachesFrame: false);
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!owner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.onlyOwnerChanges(s.owner.displayName), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ListTile(
          title: Text(l.frameName),
          subtitle: Text(name),
          trailing: owner ? const Icon(Icons.edit_outlined) : null,
          onTap: owner ? () => _rename(name) : null,
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
            child: Row(children: [
              Expanded(child: Text(l.order, style: theme.textTheme.bodyLarge)),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'random', label: Text(l.orderShuffle)),
                  ButtonSegment(value: 'sequential', label: Text(l.orderInOrder)),
                ],
                selected: {order},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _save({'display_order': v.single}),
              ),
            ]),
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
        _Section(l.sectionHardware),
        ListTile(title: Text(l.frameModel), subtitle: Text(model)),
        ListTile(
          title: Text(f.connected
              ? (f.fwVersion == null ? l.hardwareConnectedNoVersion : l.hardwareConnected(f.fwVersion!))
              : l.hardwareNotConnected),
          subtitle: f.batteryPct == null ? null : Text(l.batteryNow(f.batteryPct!)),
          leading: Icon(f.connected ? Icons.check_circle_outline : Icons.link_off),
        ),
        const Divider(height: 24),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(l.storage),
          subtitle: usage == null
              ? null
              : Text(l.storageUsed(formatBytes(usage.frame.bytes, locale), formatBytes(usage.limitBytes, locale))),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openPanel<void>(context, (_) => StorageScreen(address: _a)),
        ),
      ],
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
