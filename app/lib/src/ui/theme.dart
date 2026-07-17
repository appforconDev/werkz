import 'package:flutter/material.dart';

// Theme #1 — 1955 industrial bureaucracy. Palette from the approved style
// anchor (assets-pipeline/anchors/README.md). Stamp red + approval green are
// the only saturated accents.
class Werkz {
  static const manila = Color(0xFFE6D2A6);
  static const kraft = Color(0xFFC8B08A);
  static const cream = Color(0xFFF2E8D0);
  static const carbon = Color(0xFFD9D2C0);
  static const steel = Color(0xFF7B8086);
  static const gunmetal = Color(0xFF4C5156);
  static const machine = Color(0xFF2E3134);
  static const oil = Color(0xFF1A1C1E);
  static const stampRed = Color(0xFFB22222);
  static const approvalGreen = Color(0xFF2E7D46);

  static const mono = 'monospace';

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: cream,
      colorScheme: base.colorScheme.copyWith(
        primary: machine,
        secondary: stampRed,
        surface: manila,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: machine,
        displayColor: machine,
        fontFamily: mono,
      ),
    );
  }
}
