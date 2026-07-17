import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/pairing_payload.dart';
import '../state/providers.dart';
import 'theme.dart';

// First 60 seconds (GDD §7.1), app side: scan the QR the daemon prints, pair,
// store the session token. Manual host:port + token fallback for emulators.
//
// The scanner controller is created fresh in initState and disposed in dispose,
// so re-mounting after unpair (a brand-new State) always gets a live camera.
// Every scan produces VISIBLE feedback — silent non-reaction is forbidden.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  MobileScannerController? _scanner;
  bool _busy = false;
  bool _manual = false;
  String? _status; // neutral/positive feedback
  String? _error; // rejection feedback
  String? _lastRaw; // de-dupe repeated frames of the same code

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController();
  }

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _submit(PairingPayload p) async {
    setState(() { _busy = true; _error = null; _status = 'Requisition read — pairing…'; });
    final err = await ref.read(pairingControllerProvider.notifier).pair(p);
    if (mounted) {
      setState(() {
        _busy = false;
        _error = err;
        _status = err == null ? 'Paired. Opening the workshop…' : null;
      });
      if (err != null) _lastRaw = null; // allow a retry scan
    }
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
      // ANY scan gets feedback — never a silent non-reaction.
      setState(() {
        _status = null;
        _error = 'Unreadable code — that is not a WERKZ pairing QR.';
      });
      _lastRaw = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Werkz.cream,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(children: [
                Text('WERKZ INDUSTRIES',
                    style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 4)),
                Text('PRESENT PAIRING REQUISITION TO THE WORKSHOP TERMINAL',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.gunmetal, letterSpacing: 1)),
              ]),
            ),
            Expanded(child: _manual ? _manualEntry() : _scannerView()),
            _feedback(),
            TextButton(
              onPressed: () => setState(() { _manual = !_manual; _error = null; _status = null; }),
              child: Text(_manual ? 'USE CAMERA' : 'ENTER BY HAND (EMULATOR)',
                  style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
            ),
          ],
        ),
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
    final scanner = _scanner;
    if (scanner == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Werkz.gunmetal, width: 3)),
      child: MobileScanner(controller: scanner, onDetect: _onScan),
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
