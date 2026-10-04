// A pretend Ink Frame over real Bluetooth (docs/pairing.md), for trying Connect
// the frame on a phone before the firmware exists. Run it on a Mac or an Android
// phone, then connect it from the Ink Frame app on another device. frame_sim does
// the claiming, checking and caching; the photo it would show appears in the window.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:frame_sim/frame_sim.dart' as sim;
import 'package:path_provider/path_provider.dart';

import 'pretend_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/frame');
  final frame = PretendFrame(sim.Frame(dir));
  runApp(MaterialApp(
    title: 'Pretend frame',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2E9E4F), useMaterial3: true),
    home: FramePage(frame: frame),
  ));
  await frame.init();
}

class FramePage extends StatelessWidget {
  const FramePage({super.key, required this.frame});

  final PretendFrame frame;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: frame,
        builder: (context, _) {
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(title: Text('Pretend frame · ${frame.name}')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AspectRatio(aspectRatio: 5 / 3, child: _Screen(frame: frame)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: frame.frame.isPaired && !frame.busy ? frame.checkNow : null,
                    icon: const Icon(Icons.circle, color: Color(0xFF7BE495), size: 14),
                    label: const Text('Check now'),
                  ),
                  OutlinedButton(onPressed: frame.frame.isPaired ? frame.next : null, child: const Text('Next photo')),
                  OutlinedButton(onPressed: frame.startPairing, child: const Text('Pair again (hold 3 s)')),
                  OutlinedButton(onPressed: frame.factoryReset, child: const Text('Reset (hold 10 s)')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Text('Model ${frame.modelId}'),
                  const SizedBox(width: 16),
                  const Text('Memory card '),
                  DropdownButton<String>(
                    value: frame.cardState,
                    items: const [
                      DropdownMenuItem(value: 'ok', child: Text('OK')),
                      DropdownMenuItem(value: 'missing', child: Text('No card')),
                      DropdownMenuItem(value: 'unreadable', child: Text("Can't read it")),
                    ],
                    onChanged: (v) => v == null ? null : frame.setCard(v),
                  ),
                  const Spacer(),
                  const Text('Require pairing'),
                  Switch(
                    value: frame.requireEncryption,
                    onChanged: (v) {
                      frame.requireEncryption = v;
                      frame.startPairing();
                    },
                  ),
                ]),
                Row(children: [
                  Text('Battery ${frame.battery} %'),
                  Expanded(
                    child: Slider(
                      value: frame.battery.toDouble(),
                      max: 100,
                      divisions: 20,
                      label: '${frame.battery} %',
                      onChanged: (v) => frame.setBattery(v.round()),
                    ),
                  ),
                  const Text('(sent at the next check)'),
                ]),
                Text(
                  'Pretend Wi-Fi: any password works except "wrong"; "Far away" is never found. '
                  'hw_id ${frame.hwId}',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 24),
                for (final line in frame.log)
                  Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          );
        },
      );
}

/// What the e-paper would show.
class _Screen extends StatelessWidget {
  const _Screen({required this.frame});

  final PretendFrame frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content;
    if (frame.advertising) {
      // Like the real frame's PAIRING screen: XXXX large (the app asks you to match
      // it), then the code the phone asks for.
      final big = theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 4);
      content = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(frame.name, style: theme.textTheme.titleMedium),
        Text(frame.suffix, style: big),
        const SizedBox(height: 16),
        Text('Code', style: theme.textTheme.labelLarge),
        Text('${frame.passkey.substring(0, 3)} ${frame.passkey.substring(3)}', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Open Ink Frame on your phone → Connect the frame'),
        if (frame.central != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Phone connected')),
      ]);
    } else if (frame.showing != null) {
      content = Image.file(
        frame.showing!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, error, _) => Center(child: Text("Couldn't show ${frame.showing!.path}: $error")),
      );
    } else {
      content = Center(
        child: Text(frame.frame.isPaired ? 'Ready. Add photos in the Ink Frame app.' : 'Not set up. Hold 3 s to set up.'),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE4),
        border: Border.all(color: Colors.black87, width: 10),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.black87), child: content),
    );
  }
}
