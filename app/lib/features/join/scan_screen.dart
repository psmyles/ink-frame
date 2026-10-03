import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/frame_link.dart';
import '../../l10n/app_localizations.dart';

/// Scans an invite or "another device" QR code (phones only; computers paste).
/// Returns the link's text.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  var _done = false;
  String? _rejected; // the last QR code that wasn't ours, said only once

  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      if (FrameLink.parse(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
      if (raw != _rejected) {
        _rejected = raw;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).notAnInvite)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.scanQr)),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(onDetect: _detect),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: Text(l.scanHint, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ),
        ),
      ]),
    );
  }
}
