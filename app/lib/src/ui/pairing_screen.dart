import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/pairing_payload.dart';
import '../state/providers.dart';
import 'theme.dart';

// First 60 seconds (GDD §7.1), app side: scan the QR the daemon prints, pair,
// store the session token. Manual host:port + token fallback for emulators.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _busy = false;
  String? _error;
  bool _manual = false;
  final _payloadCtrl = TextEditingController();

  Future<void> _submit(PairingPayload p) async {
    setState(() { _busy = true; _error = null; });
    final err = await ref.read(pairingControllerProvider.notifier).pair(p);
    if (mounted) setState(() { _busy = false; _error = err; });
  }

  void _onScan(BarcodeCapture cap) {
    if (_busy) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final p = PairingPayload.tryDecode(raw);
    if (p != null) _submit(p);
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
            Expanded(
              child: _manual ? _manualEntry() : _scanner(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Werkz.stampRed, fontFamily: Werkz.mono)),
              ),
            TextButton(
              onPressed: () => setState(() => _manual = !_manual),
              child: Text(_manual ? 'USE CAMERA' : 'ENTER BY HAND (EMULATOR)',
                  style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Werkz.gunmetal, width: 3)),
      child: MobileScanner(onDetect: _onScan),
    );
  }

  Widget _manualEntry() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paste the "pair by hand" payload from the daemon:',
              style: TextStyle(fontFamily: Werkz.mono, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _payloadCtrl,
            maxLines: 4,
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'eyJ2IjoxLC…'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final p = PairingPayload.tryDecode(_payloadCtrl.text);
                    if (p == null) {
                      setState(() => _error = 'Could not decode that payload.');
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
