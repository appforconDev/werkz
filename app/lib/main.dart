import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Werkz — mobile-only, portrait-locked (CLAUDE.md stack rule).
// World layer will be Flame; overlays/HUD pure Flutter. Scaffold only.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: WerkzApp()));
}

class WerkzApp extends StatelessWidget {
  const WerkzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Werkz',
      home: const Scaffold(
        body: Center(
          child: Text('WERKZ INDUSTRIES\nThe workshop opens in P2.'),
        ),
      ),
    );
  }
}
