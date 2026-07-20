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
          const Text(
            'Narration runs on your own Claude — no API key. When something happens, '
            'your daemon asks Claude (Haiku) for one dry line. If Claude cannot run, '
            'the workshop simply stays quiet: log lines without the voice.',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal),
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
            // Task 24.2: unpairing revokes the session AND voids the workshop's
            // current QR — an accidental tap reproduces the exact "healthy WS
            // closes (1000), pairing screen, old QR rejected" device sequence.
            // The pairing screen must be reachable ONLY by deliberate action,
            // so this now confirms first.
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Werkz.cream,
                  title: const Text('UNPAIR THIS PHONE?',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  content: const Text(
                      'This revokes the phone\'s session and VOIDS the current pairing QR — '
                      'you will need to scan a fresh one (`werkz qr`) to reconnect.',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.machine)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('CANCEL', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('UNPAIR', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.stampRed)),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
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
