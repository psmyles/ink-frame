import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ble/frame_bluetooth.dart';
import '../../ble/protocol.dart';
import '../../data/frame_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/connect_frame.dart';
import '../../state/frame_admin.dart';
import '../../state/providers.dart';
import '../../state/setup.dart';
import 'dev_connect_screen.dart';

/// Opens Connect the frame over everything else (owner only).
Future<void> openConnectFrame(BuildContext context, FrameAddress address) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ConnectFrameScreen(address: address),
    ));

/// Connect the frame over Bluetooth (app-flow §6, docs/pairing.md).
class ConnectFrameScreen extends ConsumerStatefulWidget {
  const ConnectFrameScreen({super.key, required this.address});

  final FrameAddress address;

  @override
  ConsumerState<ConnectFrameScreen> createState() => _ConnectFrameScreenState();
}

class _ConnectFrameScreenState extends ConsumerState<ConnectFrameScreen> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  WifiNetwork? _picked;
  var _other = false;
  var _showPassword = false;

  AppLocalizations get l => AppLocalizations.of(context);
  ConnectFrame get _flow => ref.read(connectFrameProvider(widget.address).notifier);

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(connectFrameProvider(widget.address));
    final view = ref.watch(frameViewProvider(widget.address)).value;
    final name = view?.name ?? '';
    return Scaffold(
      appBar: AppBar(leading: const CloseButton(), title: Text(l.connectFrameTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (s.step) {
                  ConnectStep.ready => _ready(s, name, view?.summary?.frame.connected ?? false),
                  ConnectStep.finding => _waiting(l.lookingForFrame, l.lookingHint),
                  ConnectStep.choose => _choose(s),
                  ConnectStep.pairing => _pairing(s, name),
                  ConnectStep.wifi => _wifi(s),
                  ConnectStep.finishing => _finishing(s, name),
                  ConnectStep.done => _done(name),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Steps ──

  List<Widget> _ready(ConnectState s, String name, bool replacing) {
    final theme = Theme.of(context);
    final devMode = ref.watch(devModeProvider).value ?? false;
    return [
      const SizedBox(height: 16),
      const Center(child: _FrameShowingCode()),
      const SizedBox(height: 24),
      Text(l.connectReadyTitle, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(l.connectReadyBody),
      if (replacing) ...[
        const SizedBox(height: 8),
        Text(l.connectReplaces(name), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      ],
      ..._problem(s, name),
      const SizedBox(height: 24),
      FilledButton(onPressed: _flow.start, child: Text(s.problem == null ? l.findFrame : l.tryAgain)),
      if (s.problem == ConnectProblem.permissionDenied && _settingsUrl != null)
        TextButton(onPressed: () => launchUrl(_settingsUrl!), child: Text(l.openSettings)),
      if (devMode)
        TextButton(
          onPressed: () async {
            final connected = await Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => DevConnectScreen(address: widget.address),
            ));
            if (connected == true && mounted) Navigator.of(context).pop();
          },
          child: Text(l.connectWithCode),
        ),
    ];
  }

  /// Bluetooth permission settings, where a link to them exists.
  Uri? get _settingsUrl => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => Uri.parse('app-settings:'),
        TargetPlatform.macOS => Uri.parse('x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth'),
        _ => null,
      };

  List<Widget> _waiting(String title, String hint) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 48),
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 24),
      Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(hint, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
    ];
  }

  List<Widget> _choose(ConnectState s) {
    final theme = Theme.of(context);
    return [
      Text(l.whichFrame, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(l.whichFrameHint),
      const SizedBox(height: 12),
      for (final f in s.found)
        Card(
          child: ListTile(
            leading: const Icon(Icons.crop_landscape),
            title: Text(f.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _flow.choose(f),
          ),
        ),
      const SizedBox(height: 16),
      const LinearProgressIndicator(),
    ];
  }

  List<Widget> _pairing(ConnectState s, String name) {
    if (s.problem == null) return _waiting(l.pairingTitle, l.pairingHint);
    if (s.problem == ConnectProblem.modelMismatch) return _modelMismatch(s, name);
    return [
      ..._problem(s, name),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _flow.retry,
        child: Text(s.problem == ConnectProblem.linkedElsewhere ? l.startAgain : l.tryAgain),
      ),
    ];
  }

  List<Widget> _modelMismatch(ConnectState s, String name) {
    final models = ref.watch(backendBundleProvider).value?.models ?? const [];
    String modelName(String id) => models.where((m) => m.id == id).firstOrNull?.name ?? id;
    final frameModel = ref.watch(frameViewProvider(widget.address)).value?.summary?.frame.modelId ?? '';
    final device = modelName(s.info?.modelId ?? '');
    final count = ref.watch(usageProvider(widget.address)).value?.frame.images ?? 0;
    return [
      const SizedBox(height: 16),
      Text(l.modelMismatch(device, name, modelName(frameModel))),
      const SizedBox(height: 8),
      Text(l.changeModelConfirm(count, name, device, modelName(frameModel))),
      if (s.detail != null && (ref.watch(devModeProvider).value ?? false)) Text(s.detail!),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: s.busy ? null : _flow.switchModel,
        child: s.busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(l.switchModel),
      ),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
    ];
  }

  List<Widget> _wifi(ConnectState s) {
    final theme = Theme.of(context);
    final picked = _picked;
    final ssid = _other ? _ssid.text.trim() : picked?.ssid ?? '';
    final needsPassword = _other || (picked?.secure ?? false);
    final ready = ssid.isNotEmpty && (!needsPassword || _other || _password.text.length >= 8);
    return [
      Text(l.wifiTitle, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(l.wifiHint),
      ..._problem(s, ''),
      const SizedBox(height: 12),
      for (final n in s.networks)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (n.bars) {
            3 => Icons.wifi,
            2 => Icons.wifi_2_bar,
            _ => Icons.wifi_1_bar,
          }),
          title: Text(n.ssid),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (n.secure) Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
            if (!_other && picked?.ssid == n.ssid) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, color: theme.colorScheme.primary),
            ],
          ]),
          selected: !_other && picked?.ssid == n.ssid,
          onTap: () => setState(() {
            _picked = n;
            _other = false;
          }),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.add),
        title: Text(l.otherNetwork),
        selected: _other,
        onTap: () => setState(() => _other = true),
      ),
      if (s.scanningWifi) ...[
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(l.wifiScanning, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      ] else
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _flow.scanWifi, icon: const Icon(Icons.refresh), label: Text(l.scanAgain)),
        ),
      if (_other) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _ssid,
          autocorrect: false,
          decoration: InputDecoration(labelText: l.networkName),
          onChanged: (_) => setState(() {}),
        ),
      ],
      if (needsPassword) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l.wifiPassword,
            suffixIcon: IconButton(
              tooltip: _showPassword ? l.hidePassword : l.showPassword,
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => ready ? _flow.join(ssid, _password.text) : null,
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: ready ? () => _flow.join(ssid, needsPassword ? _password.text : '') : null,
        child: Text(l.connectAction),
      ),
    ];
  }

  List<Widget> _finishing(ConnectState s, String name) {
    final theme = Theme.of(context);
    final at = switch (s.progress) {
      null || LinkState.wifiConnecting => 0,
      LinkState.claiming => 1,
      _ => 2,
    };
    Widget row(int i, String title) {
      final icon = i < at
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : i == at
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : Icon(Icons.radio_button_unchecked, color: theme.colorScheme.outline);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: Text(title, style: TextStyle(fontWeight: i == at ? FontWeight.w600 : null)),
      );
    }

    return [
      Text(l.connectingNamed(name), style: theme.textTheme.headlineSmall),
      const SizedBox(height: 16),
      row(0, l.stageJoinWifi(s.ssid ?? '')),
      row(1, l.stageLinking(name)),
      row(2, l.stageGettingPhotos),
    ];
  }

  List<Widget> _done(String name) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 24),
      Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
      const SizedBox(height: 16),
      Text(l.frameConnected(name), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(l.frameConnectedBody, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.done)),
    ];
  }

  // ── Problems (app-flow §6.2) ──

  List<Widget> _problem(ConnectState s, String name) {
    final p = s.problem;
    if (p == null) return const [];
    final theme = Theme.of(context);
    final ssid = s.ssid ?? '';
    final text = switch (p) {
      ConnectProblem.bluetoothOff => l.bluetoothOff,
      ConnectProblem.permissionDenied => l.bluetoothDenied,
      ConnectProblem.noBluetooth => l.noBluetooth,
      ConnectProblem.noFrameFound => l.noFrameFound,
      ConnectProblem.wrongCode => l.wrongCode,
      ConnectProblem.cancelled => l.pairingCancelled,
      ConnectProblem.modelMismatch => '',
      ConnectProblem.linkedElsewhere => l.linkedElsewhere,
      ConnectProblem.wifiFailed => switch (s.wifiReason) {
          'auth' => l.wifiWrongPassword(ssid),
          'not_found' => l.wifiNotFound(ssid),
          _ => l.wifiFailed(ssid),
        },
      ConnectProblem.unreachable => l.frameNoInternet(ssid),
      ConnectProblem.offline => l.phoneOffline,
      ConnectProblem.lost => l.connectionLost,
      ConnectProblem.failed => l.somethingWrong,
    };
    final dev = (ref.watch(devModeProvider).value ?? false) && s.detail != null ? '\n${s.detail}' : '';
    final serious = p != ConnectProblem.cancelled && p != ConnectProblem.noFrameFound;
    return [
      const SizedBox(height: 16),
      Text('$text$dev', style: serious ? TextStyle(color: theme.colorScheme.error) : null),
      if (p == ConnectProblem.noFrameFound) ...[
        const SizedBox(height: 8),
        for (final tip in [l.noFrameTipCode, l.noFrameTipCloser, l.noFrameTipButton])
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  '),
              Expanded(child: Text(tip)),
            ]),
          ),
      ],
    ];
  }
}

/// The frame showing its name and pairing code, with the green button marked.
class _FrameShowingCode extends StatelessWidget {
  const _FrameShowingCode();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: 220,
        height: 150,
        child: Stack(children: [
          Container(
            width: 220,
            height: 140,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border.all(color: scheme.onSurface, width: 6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${Pairing.namePrefix}1A2B', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text('123 456', style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w600)),
            ]),
          ),
          Positioned(
            right: 18,
            bottom: 0,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF2E9E4F),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 3),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// What [FoundFrame] lists show when the name hasn't arrived yet.
extension FoundFrameName on FoundFrame {
  String get label => name.isEmpty ? Pairing.namePrefix : name;
}
