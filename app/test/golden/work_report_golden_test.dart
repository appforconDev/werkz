// Task 23B: goldens for the work-order COMPLETION REPORT view (static UI —
// goldenable), multi-device per the standing screenshot rule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/widgets/work_report_sheet.dart';
import 'harness.dart';

const _report = 'ROOT AUDIT — 2026-07-19\n\n'
    'INVENTORY OF THE PROJECT ROOT:\n'
    '  - README.md ......... project overview, current\n'
    '  - package.json ...... 12 dependencies, none flagged\n'
    '  - src/ .............. 14 modules, entry at index.ts\n'
    '  - test/ ............. 9 suites, all referenced\n'
    '  - .env.example ...... documents 3 required vars\n\n'
    'IRREGULARITIES: none observed.\n'
    'RECOMMENDATION: no action required. File under routine.\n';

Widget _sheet() => MaterialApp(
      theme: Werkz.theme(),
      home: Scaffold(
        body: WorkReportSheet(
          report: _report,
          summary: 'Audit filed. Root inspected, nothing seized.',
          turns: 2,
        ),
      ),
    );

void main() {
  testWidgets('work report — iPhone 12', (t) async {
    await pumpGolden(t, app: _sheet(), name: 'work_report');
  });
  testWidgets('work report — iPhone SE', (t) async {
    await pumpGolden(t, app: _sheet(), name: 'work_report_se', device: deviceSE);
  });
  testWidgets('work report — iPhone 15 Pro Max', (t) async {
    await pumpGolden(t, app: _sheet(), name: 'work_report_promax', device: deviceProMax);
  });
}
