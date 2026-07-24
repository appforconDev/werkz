// Task 39: Advisor Consultation app side — session start, send/reply, waiting,
// degradation, and the consult→dispatch bridge (plan → Form 17-B directive).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/state/consultation.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/work_order_sheet.dart';

class _FakeClient extends DaemonClient {
  _FakeClient()
      : super(payload: const PairingPayload(host: '127.0.0.1', port: 1, token: 't'), sessionToken: 's');
  @override
  void connect() {}
  @override
  void dispose() {}
}

class _FakeStorage extends FlutterSecureStorage {
  const _FakeStorage();
  static final Map<String, String> _store = {
    'werkz.sessionToken': 'sess', 'werkz.host': '127.0.0.1', 'werkz.port': '47100',
    'werkz.pairToken': 'tok', 'werkz.seenFirstRun': '1',
  };
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async => _store[key];
}

Future<ProviderContainer> _boot() async {
  final container = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(const _FakeStorage()),
    daemonClientBuilderProvider.overrideWithValue((p) => _FakeClient()),
  ]);
  addTearDown(container.dispose);
  await container.read(pairingControllerProvider.future);
  container.read(workshopProvider);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  tearDown(() {
    DaemonClient.consultStartOverride = null;
    DaemonClient.consultSendOverride = null;
  });

  test('a turn: send → waiting → advisor reply appends; latestPlan tracks it', () async {
    final container = await _boot();
    DaemonClient.consultStartOverride = () async => ('sess-1', null);
    DaemonClient.consultSendOverride = (id, msg) async => ('Step 1: read auth.ts. Step 2: add tests.', null);

    final ctrl = container.read(consultationProvider.notifier);
    await ctrl.send('plan the auth refactor');
    final s = container.read(consultationProvider);
    expect(s.turns.length, 2);
    expect(s.turns[0].role, ConsultRole.operator);
    expect(s.turns[1].role, ConsultRole.advisor);
    expect(s.waiting, isFalse);
    expect(s.latestPlan, contains('Step 1'));
  });

  test('degradation: Advisor unavailable → loud-but-kind error, waiting cleared', () async {
    final container = await _boot();
    DaemonClient.consultStartOverride = () async => ('sess-1', null);
    DaemonClient.consultSendOverride = (id, msg) async => (null, 'Advisor unavailable — no Claude found.');

    await container.read(consultationProvider.notifier).send('hi');
    final s = container.read(consultationProvider);
    expect(s.waiting, isFalse);
    expect(s.error, contains('Advisor unavailable'));
    // The operator memo stays visible (only the operator turn was added).
    expect(s.turns.where((t) => t.role == ConsultRole.operator).length, 1);
  });

  test('latestPlan is the newest Advisor reply — the directive the bridge hands off', () async {
    final container = await _boot();
    DaemonClient.consultStartOverride = () async => ('sess-1', null);
    var n = 0;
    DaemonClient.consultSendOverride = (id, msg) async => ('PLAN v${++n}', null);
    final ctrl = container.read(consultationProvider.notifier);
    await ctrl.send('draft one');
    await ctrl.send('refine it');
    expect(container.read(consultationProvider).latestPlan, 'PLAN v2', reason: 'newest advisory is dispatched');
  });

  // Part B: raw Markdown must NEVER reach the screen. The daemon prompt asks for
  // plain text; stripMarkdown is the fallback. These fail if any markup survives.
  test('stripMarkdown removes bold/italic, backticks, headers and bullets', () {
    expect(stripMarkdown('**TASK DISPATCH REQUIRED**'), 'TASK DISPATCH REQUIRED');
    expect(stripMarkdown('edit `pairing.ts` now'), 'edit pairing.ts now');
    expect(stripMarkdown('## Plan\n- step one\n* step two'), 'Plan\nstep one\nstep two');
    expect(stripMarkdown('use *emphasis* and ~~cut~~'), 'use emphasis and cut');
    // Code identifiers and paths survive untouched.
    expect(stripMarkdown('call some_func in a/b/c.ts'), 'call some_func in a/b/c.ts');
    // No markup character can leak.
    for (final ch in ['*', '`']) {
      expect(stripMarkdown('a ${ch}b$ch c').contains(ch), isFalse, reason: '$ch must not survive');
    }
  });

  test('an Advisor reply with Markdown is sanitised before it becomes a turn', () async {
    final container = await _boot();
    DaemonClient.consultStartOverride = () async => ('sess-1', null);
    DaemonClient.consultSendOverride = (id, msg) async =>
        ('**PLAN**\n- edit `auth.ts`\n- add `3` tests', null);
    final ctrl = container.read(consultationProvider.notifier);
    await ctrl.send('plan it');
    final s = container.read(consultationProvider);
    final shown = s.turns.last.text; // exactly what the UI renders
    expect(shown.contains('*'), isFalse, reason: 'no asterisks reach the UI');
    expect(shown.contains('`'), isFalse, reason: 'no backticks reach the UI');
    // The dispatched directive (Form 17-B) is clean too.
    expect(s.latestPlan!.contains('*'), isFalse);
    expect(s.latestPlan!.contains('`'), isFalse);
  });

  testWidgets('the consult→dispatch bridge pre-fills Form 17-B with the plan (task 39 C)', (tester) async {
    // The bridge = showWorkOrderSheet(initialDirective: plan). Test the pre-fill
    // directly (the full Advisor screen loads room art — covered by the golden).
    await tester.pumpWidget(MaterialApp(
      theme: Werkz.theme(),
      home: Builder(builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showWorkOrderSheet(context, initialDirective: 'PLAN: refactor auth; add 3 tests.'),
            child: const Text('open'),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet animates in

    expect(find.text('FORM 17-B — REQUEST FOR AGENT DISPATCH'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PLAN: refactor auth; add 3 tests.'), findsOneWidget,
        reason: 'the plan is pre-filled — no re-typing');
  });
}
