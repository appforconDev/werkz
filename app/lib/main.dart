import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/state/providers.dart';
import 'src/ui/pairing_screen.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/first_run_screen.dart';
import 'src/ui/theme.dart';

// Werkz — mobile-only, portrait-locked (CLAUDE.md stack rule). Flame is for
// the world layer later; this P2 slice is pure Flutter widgets.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: WerkzApp()));
}

class WerkzApp extends StatelessWidget {
  const WerkzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Werkz',
      debugShowCheckedModeBanner: false,
      theme: Werkz.theme(),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing = ref.watch(pairingControllerProvider);
    return pairing.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (stored) {
        if (stored == null) return const PairingScreen();
        // First-run tour after the first successful pairing (once, skippable).
        final seen = ref.watch(firstRunSeenProvider).asData?.value ?? true;
        return seen ? const HomeScreen() : const FirstRunScreen();
      },
    );
  }
}
