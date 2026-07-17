// Golden-screenshot harness (CLAUDE.md rule): render a screen at the iPhone-12
// logical size (390×844) and snapshot it to app/test/goldens/. Layout, safe
// area, overflow banners, and spacing are all faithful; CC views each PNG.
//
// SAFE AREA (task 16 A — the harness lied): the insets MUST be set on
// tester.view via FakeViewPadding, NOT via a wrapping MediaQuery. MaterialApp
// builds its own MediaQuery.fromView(view) which shadows any ancestor
// MediaQuery, so an outer wrapper is silently ignored — every "verified"
// golden was rendered WITHOUT the notch/home-indicator. iPhone 12: top 47,
// bottom 34 (logical; physical == logical here because dpr = 1.0).
//
// Callers build the full ProviderScope+MaterialApp inline (so the `Override`
// list type is inferred — flutter_riverpod 3.x doesn't export the name).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';

const iphone12 = Size(390, 844);

/// A daemon client that never opens a socket.
class GoldenClient extends DaemonClient {
  GoldenClient(PairingPayload p, String s) : super(payload: p, sessionToken: s);
  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  Future<(bool, String?)> narrationKeyStatus() async => (false, null);
}

class GoldenStorage extends FlutterSecureStorage {
  final Map<String, String> data;
  GoldenStorage(this.data);
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => data[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value == null) { data.remove(key); } else { data[key] = value; }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => data.remove(key);
  @override
  Future<void> deleteAll({dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => data.clear();
}

/// Pumps a caller-built [app] (ProviderScope+MaterialApp) at 390×844 and
/// snapshots the top-level MaterialApp.
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget app,
  required String name,
  Duration settle = const Duration(milliseconds: 700),
}) async {
  await pumpGoldenApp(tester, app: app, settle: settle);
  await expectGolden(tester, name);
}

/// Pump [app] at the iPhone-12 size and settle, but do NOT capture — lets a test
/// tap/interact (open a sheet) before capturing with [expectGolden].
Future<void> pumpGoldenApp(
  WidgetTester tester, {
  required Widget app,
  Duration settle = const Duration(milliseconds: 700),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = iphone12; // logical == physical at dpr 1.0
  // Real iPhone-12 safe-area insets set ON THE VIEW so MediaQuery.fromView (which
  // MaterialApp builds internally) actually reports them. This is the fix.
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(app);
  // Let asset images decode so rooms render in the golden.
  await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump();
  // Explicitly advance past deferred timers (e.g. the 500ms overlay gate) —
  // pumpAndSettle alone returns early when nothing is animating.
  await tester.pump(settle);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> expectGolden(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/$name.png'));
}

Map<String, String> pairedStore({bool seenFirstRun = true}) => {
      'werkz.sessionToken': 'sess',
      'werkz.host': '127.0.0.1',
      'werkz.port': '47100',
      'werkz.pairToken': 'tok',
      if (seenFirstRun) 'werkz.seenFirstRun': '1',
    };
