import 'package:flutter/material.dart';
import '../theme.dart';

// The diff core — ALWAYS visible in every decision overlay (GDD/domain rule).
// Monospace, scrollable, red/green line tinting. Lines come from the daemon's
// device-zone diffCore (event-model §4.3).
class DiffCore extends StatelessWidget {
  final List<Map<String, dynamic>> lines; // {sign: '+'/'-'/' ', text}
  const DiffCore({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Werkz.oil,
        border: Border.all(color: Werkz.gunmetal, width: 2),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('(no diff — command decision)',
                  style: TextStyle(color: Werkz.steel, fontFamily: Werkz.mono, fontSize: 12)),
            )
          : Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final sign = (lines[i]['sign'] as String?) ?? ' ';
                  final text = (lines[i]['text'] as String?) ?? '';
                  final (bg, fg) = switch (sign) {
                    '+' => (Werkz.approvalGreen.withValues(alpha: 0.20), const Color(0xFFB9F5C8)),
                    '-' => (Werkz.stampRed.withValues(alpha: 0.20), const Color(0xFFF5B9B9)),
                    _ => (Colors.transparent, Werkz.carbon),
                  };
                  return Container(
                    color: bg,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text(sign,
                              style: TextStyle(color: fg, fontFamily: Werkz.mono, fontSize: 12, height: 1.4)),
                        ),
                        Expanded(
                          child: Text(text,
                              style: TextStyle(color: fg, fontFamily: Werkz.mono, fontSize: 12, height: 1.4)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
