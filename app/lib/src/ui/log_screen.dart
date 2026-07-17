import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../state/narration.dart';
import 'theme.dart';

// Full scrollable incident-log history (tap target from the ambient strip).
class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workshopProvider);
    final lines = ws.feed.reversed.toList();
    return Scaffold(
      backgroundColor: Werkz.cream,
      appBar: AppBar(
        backgroundColor: Werkz.machine,
        foregroundColor: Werkz.cream,
        title: const Text('INCIDENT LOG',
            style: TextStyle(fontFamily: Werkz.mono, letterSpacing: 3, fontSize: 15)),
      ),
      body: lines.isEmpty
          ? const Center(
              child: Text('Quiet shift. The workers wait.',
                  style: TextStyle(fontFamily: Werkz.mono, color: Werkz.gunmetal)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Werkz.carbon),
              itemBuilder: (_, i) {
                final e = lines[i];
                final narrated = ws.narration[e.eventId];
                return ListTile(
                  dense: true,
                  leading: Text(e.timestamp.length >= 19 ? e.timestamp.substring(11, 19) : '',
                      style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.steel)),
                  title: Text(narrated ?? narrate(e),
                      style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, color: Werkz.machine)),
                  subtitle: narrated != null
                      ? const Text('narrated', style: TextStyle(fontFamily: Werkz.mono, fontSize: 8, color: Werkz.approvalGreen))
                      : null,
                );
              },
            ),
    );
  }
}
