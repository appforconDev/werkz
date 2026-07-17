import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/pairing_payload.dart';
import '../state/providers.dart';
import 'theme.dart';

// Camera pairing screen — pushed from the onboarding screen, so it is created
// fresh on every entry (including after unpair → repair). We let MobileScanner
// OWN its controller: in mobile_scanner 7.x the widget only registers the
// app-lifecycle observer and manages start/stop/dispose when it owns the
// controller (widget.controller == null). Passing our own controller (the
// task-10 change) skipped that and rendered a black preview on iOS — so we no
// longer pass one.
//
// On successful pairing this route POPS itself: the root swaps its home to the
// workshop underneath the pushed route, so without a pop the app would hang on
// "Paired…". A 5s watchdog surfaces WHY if navigation ever stalls.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _busy = false;
  bool _manual = false;
  String? _status;
  String? _error;
  String? _lastRaw;
  Timer? _watchdog;

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  Future<void> _submit(PairingPayload p) async {
    setState(() { _busy = true; _error = null; _status = 'Requisition read — pairing…'; });
    final err = await ref.read(pairingControllerProvider.notifier).pair(p);
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _error = err; _status = null; _lastRaw = null; });
      return;
    }
    // Success: the root now shows the workshop under this pushed route — pop to
    // reveal it. Watchdog: if we're somehow still here after 5s, say why.
    setState(() { _status = 'Paired. Opening the workshop…'; });
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        final conn = ref.read(workshopProvider).conn.name;
        setState(() { _busy = false; _error = 'Workshop did not open (state: $conn). Pull down to retry.'; _status = null; });
      }
    });
    Navigator.of(context).maybePop();
  }

  void _onScan(BarcodeCapture cap) {
    if (_busy) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw == _lastRaw) return;
    _lastRaw = raw;
    final p = PairingPayload.tryDecode(raw);
    if (p != null) {
      _submit(p);
    } else {
      setState(() { _status = null; _error = 'Unreadable code — that is not a WERKZ pairing QR.'; });
      _lastRaw = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Werkz.cream,
      appBar: AppBar(
        backgroundColor: Werkz.machine,
        foregroundColor: Werkz.cream,
        title: const Text('SCAN PAIRING QR',
            style: TextStyle(fontFamily: Werkz.mono, letterSpacing: 2, fontSize: 14)),
      ),
      body: Column(
        children: [
          Expanded(child: _manual ? _manualEntry() : _scannerView()),
          _feedback(),
          TextButton(
            onPressed: () => setState(() { _manual = !_manual; _error = null; _status = null; }),
            child: Text(_manual ? 'USE CAMERA' : 'ENTER BY HAND (EMULATOR)',
                style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _feedback() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Werkz.stampRed, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Werkz.stampRed, fontFamily: Werkz.mono, fontSize: 12))),
        ]),
      );
    }
    if (_status != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(_status!, textAlign: TextAlign.center, style: const TextStyle(color: Werkz.approvalGreen, fontFamily: Werkz.mono, fontSize: 12)),
      );
    }
    return const SizedBox(height: 12);
  }

  Widget _scannerView() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Werkz.gunmetal, width: 3)),
      // MobileScanner owns its controller → correct lifecycle + live preview.
      child: MobileScanner(onDetect: _onScan),
    );
  }

  Widget _manualEntry() {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paste the "pair by hand" payload from the daemon:',
              style: TextStyle(fontFamily: Werkz.mono, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: 4,
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'eyJ2IjoxLC…'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final p = PairingPayload.tryDecode(ctrl.text);
                    if (p == null) {
                      setState(() { _status = null; _error = 'Could not decode that payload.'; });
                    } else {
                      _submit(p);
                    }
                  },
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('PAIR'),
          ),
        ],
      ),
    );
  }
}
