import 'package:flutter/foundation.dart';
import '../debug_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../build_info.dart';
import '../daemon/daemon_client.dart';
import '../state/layout_tuning.dart';
import '../state/providers.dart';
import 'theme.dart';
import 'first_run_screen.dart';

// Connection / session / mode details + key management + unpair (tap target
// from the status bar).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    setState(() { _busy = true; _msg = null; });
    // Store locally first so we can retry on the next connect if the daemon is
    // unreachable right now.
    if (key.isEmpty) {
      await ref.read(secureStorageProvider).delete(key: 'werkz.narrationKey');
    } else {
      await ref.read(secureStorageProvider).write(key: 'werkz.narrationKey', value: key);
    }
    final ok = await ref.read(workshopProvider.notifier).setNarrationKey(key);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = ok
            ? (key.isEmpty ? 'Key cleared — templates only.' : 'Saved → daemon confirmed. Narration active.')
            : 'Saved on device — the workshop is offline; will retry on reconnect.';
        if (ok) _keyCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workshopProvider);
    final pairing = ref.watch(pairingControllerProvider).asData?.value;
    final conn = switch (ws.conn) {
      ConnState.connected => 'connected',
      ConnState.connecting => 'connecting…',
      ConnState.disconnected => 'closed',
    };

    return Scaffold(
      backgroundColor: Werkz.cream,
      appBar: AppBar(
        backgroundColor: Werkz.machine,
        foregroundColor: Werkz.cream,
        // Long-press opens the debug LAYOUT TUNING panel over the home screen
        // (task 17 C) — gated on kWerkzDebugTools so it survives release (task 21).
        title: GestureDetector(
          onLongPress: kWerkzDebugTools
              ? () {
                  ref.read(layoutTuningPanelVisibleProvider.notifier).show();
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('WORKSHOP OFFICE',
              style: TextStyle(fontFamily: Werkz.mono, letterSpacing: 3, fontSize: 15)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('CONNECTION'),
          _row('Status', conn),
          if (pairing != null) _row('Workshop at', '${pairing.payload.host}:${pairing.payload.port}'),
          // Hide the mode row until the daemon actually knows it (first tool call).
          if (ws.permissionMode != null) _row('Mode', ws.permissionMode!),
          if (ws.permissionMode != null) _row('Oversight', ws.autopilot ? 'AUTOPILOT (bypassed)' : 'manual'),
          const SizedBox(height: 24),

          _section('NARRATION'),
          _NarrationStatusBlock(active: ws.narrationActive, last4: ws.narrationLast4),
          const SizedBox(height: 10),
          const Text(
            'Your Anthropic (Haiku) API key powers narration. It is sent to your '
            'daemon and stays on that machine — never to us, never in git.',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'sk-ant-…  (blank to clear)'),
          ),
          // Inline status UNDER the field — never a covering sheet (B2).
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg!, style: const TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.approvalGreen)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _saveKey,
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SEND KEY TO WORKSHOP'),
          ),
          const SizedBox(height: 24),

          _section('ACCESSIBILITY'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: Werkz.approvalGreen,
            title: const Text('Reduced effects',
                style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, color: Werkz.machine)),
            subtitle: const Text('Skip the stamp-slam animation and momentum on decisions.',
                style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.gunmetal)),
            value: ref.watch(reducedEffectsProvider).asData?.value ?? false,
            onChanged: (v) => ref.read(reducedEffectsProvider.notifier).set(v),
          ),
          const SizedBox(height: 16),

          _section('WORKSHOP'),
          TextButton(
            onPressed: () {
              ref.read(firstRunSeenProvider.notifier).reopen();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FirstRunScreen()));
            },
            child: const Text('REPLAY INTRODUCTION', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(pairingControllerProvider.notifier).unpair();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('UNPAIR THIS PHONE', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.stampRed)),
          ),
          const SizedBox(height: 16),

          // Build stamp (task 17 B): every device report starts from a known
          // build. UNSTAMPED means the build skipped tool/device-run.sh.
          _section('BUILD'),
          _row('App build', werkzBuildStamp),
          _row('Mode', kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('— $t —',
            style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, letterSpacing: 2, color: Werkz.gunmetal, fontWeight: FontWeight.bold)),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.gunmetal)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.machine, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
}

// Clear state block (B4): active with key suffix, or "no key — templates only".
class _NarrationStatusBlock extends StatelessWidget {
  final bool active;
  final String? last4;
  const _NarrationStatusBlock({required this.active, required this.last4});

  @override
  Widget build(BuildContext context) {
    final color = active ? Werkz.approvalGreen : Werkz.steel;
    final text = active
        ? '● NARRATION ACTIVE${last4 != null ? ' — key ending …$last4' : ''}'
        : '○ No key — templates only';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: color), color: Werkz.carbon),
      child: Text(text,
          style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
