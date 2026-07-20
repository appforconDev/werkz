// Task 38: Form 22-C app side — the filing rides on job.completed → a pending
// filing + swipe card; the summary follows via filing.summary; approve
// commits+pushes (or shows a loud error), hold logs, replay never re-cards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/models/werkz_event.dart';
import 'package:werkz_app/src/state/providers.dart';
import 'package:werkz_app/src/ui/theme.dart';
import 'package:werkz_app/src/ui/widgets/completion_filing_card.dart';

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

WerkzEvent _ev(String id, String type, Map<String, dynamic> p) =>
    WerkzEvent(eventId: id, timestamp: '2026-07-20T00:00:00.000Z', eventType: type, severity: 'info', workerId: 'WX-9B72', payload: p);

Map<String, dynamic> _filingPayload() => {
      'source': 'work-order', 'ok': true, 'turns': 3,
      'filing': {'files': ['src/a.ts', 'src/b.ts'], 'fileCount': 2, 'stat': ' 2 files changed, 8 insertions(+)'},
    };

Future<(ProviderContainer, _FakeClient)> _boot() async {
  late _FakeClient fake;
  final container = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(const _FakeStorage()),
    daemonClientBuilderProvider.overrideWithValue((p) => fake = _FakeClient()),
  ]);
  addTearDown(container.dispose);
  await container.read(pairingControllerProvider.future);
  container.read(workshopProvider);
  await Future<void>.delayed(Duration.zero);
  return (container, fake);
}

void main() {
  test('a live job.completed with a filing raises a pending Form 22-C', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'job.completed', _filingPayload()), false);
    final f = container.read(workshopProvider).pendingFiling;
    expect(f, isNotNull);
    expect(f!.jobEventId, 'e1');
    expect(f.files, ['src/a.ts', 'src/b.ts']);
    expect(f.fileCount, 2);
    expect(f.summary, isNull, reason: 'summary follows separately');

    // The dry Haiku diff line arrives and merges in.
    fake.onEvent!(_ev('e2', 'filing.summary', {'refEventId': 'e1', 'text': 'Tidy the a/b imports.'}), false);
    expect(container.read(workshopProvider).pendingFiling!.summary, 'Tidy the a/b imports.');
  });

  test('a CLEAN completion (no filing) raises no 22-C', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'job.completed', {'source': 'work-order', 'ok': true, 'turns': 1}), false);
    expect(container.read(workshopProvider).pendingFiling, isNull);
  });

  test('replayed job.completed with a filing does NOT re-card (task 16 B)', () async {
    final (container, fake) = await _boot();
    fake.onWelcome!(const [], false, null, null);
    fake.onEvent!(_ev('e9', 'job.completed', _filingPayload()), true);
    expect(container.read(workshopProvider).pendingFiling, isNull);
  });

  test('approve → commit+push ok → card clears + FILED in the LOG', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'job.completed', _filingPayload()), false);
    DaemonClient.approveFilingOverride = () async => (true, null);
    addTearDown(() => DaemonClient.approveFilingOverride = null);

    final (ok, err) = await container.read(workshopProvider.notifier).approveFiling();
    expect(ok, isTrue);
    expect(err, isNull);
    final ws = container.read(workshopProvider);
    expect(ws.pendingFiling, isNull, reason: 'card cleared');
    expect(ws.feed.last.payload['localText'], contains('filed'));
  });

  test('approve → push FAILS → loud error, card STAYS (no silent success)', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'job.completed', _filingPayload()), false);
    DaemonClient.approveFilingOverride = () async => (false, 'git push failed — No configured push destination.');
    addTearDown(() => DaemonClient.approveFilingOverride = null);

    final (ok, err) = await container.read(workshopProvider.notifier).approveFiling();
    expect(ok, isFalse);
    expect(err, contains('push failed'));
    expect(container.read(workshopProvider).pendingFiling, isNotNull, reason: 'changes stay, card stays');
  });

  test('hold → no commit, card clears, HELD in the LOG', () async {
    final (container, fake) = await _boot();
    fake.onEvent!(_ev('e1', 'job.completed', _filingPayload()), false);
    container.read(workshopProvider.notifier).holdFiling();
    final ws = container.read(workshopProvider);
    expect(ws.pendingFiling, isNull);
    expect(ws.feed.last.payload['localText'], contains('HELD'));
  });

  testWidgets('the 22-C card swipes: right approves, and a push failure keeps it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var approved = false;
    Widget app(CompletionFiling f) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: Werkz.theme(),
            home: Scaffold(
              body: Center(
                child: CompletionFilingCard(
                  filing: f,
                  onApprove: () async { approved = true; return (false, 'git push failed — auth'); },
                  onHold: () {},
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(app(const CompletionFiling(
        jobEventId: 'e1', files: ['a.ts'], fileCount: 1, stat: '1 file changed', summary: 'tidy a')));
    expect(find.text('FORM 22-C · COMPLETION FILING'), findsOneWidget);

    await tester.drag(find.byType(CompletionFilingCard), const Offset(500, 0)); // right swipe
    await tester.pumpAndSettle();
    expect(approved, isTrue, reason: 'right swipe called approve');
    expect(find.byType(CompletionFilingCard), findsOneWidget, reason: 'push failed → card stays');
    expect(find.textContaining('push failed'), findsOneWidget, reason: 'loud error shown inline');
  });
}
