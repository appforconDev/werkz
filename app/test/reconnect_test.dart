// Task 22 B: reconnect resilience. Pure backoff/jitter/close-reason math, plus a
// fake-socket heartbeat test proving a SILENT drop (no close frame, NAT/power-save)
// is detected within a couple of ping intervals and triggers a reconnect.
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';

class _FakeSink implements WebSocketSink {
  final StreamController inbound;
  _FakeSink(this.inbound);
  @override
  void add(dynamic data) {}
  @override
  Future close([int? code, String? reason]) async {
    if (!inbound.isClosed) await inbound.close();
  }
  @override
  void addError(Object e, [StackTrace? s]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future get done => inbound.done;
}

class _FakeChannel implements WebSocketChannel {
  final inbound = StreamController<dynamic>();
  @override
  Stream get stream => inbound.stream;
  @override
  WebSocketSink get sink => _FakeSink(inbound);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future<void>.value();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('backoff schedule', () {
    test('exponential, base 1s, capped at 30s', () {
      var b = kBackoffBaseMs;
      final seq = [b];
      for (var i = 0; i < 10; i++) {
        b = nextBackoffMs(b);
        seq.add(b);
      }
      expect(seq[0], 1000);
      expect(seq[1], 2000);
      expect(seq[2], 4000);
      expect(seq.last, 30000, reason: 'capped'); // 1→2→4→8→16→30(cap)
      expect(seq.every((x) => x >= 1000 && x <= 30000), isTrue);
    });

    test('jitter stays within ±30% of the backoff', () {
      for (final r in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final d = jitteredBackoff(10000, r).inMilliseconds;
        expect(d, inInclusiveRange(7000, 13000));
      }
      // full spread across the random range
      expect(jitteredBackoff(10000, 0.0).inMilliseconds, 7000);
      expect(jitteredBackoff(10000, 1.0).inMilliseconds, 13000);
    });
  });

  group('close reason instrumentation', () {
    test('friendly strings per close code + the silent-drop path', () {
      expect(describeClose(null, null, silentDrop: true), contains('silent drop'));
      expect(describeClose(1000, null), contains('normal'));
      expect(describeClose(1001, null), contains('going away'));
      expect(describeClose(1006, null), contains('abnormal'));
      expect(describeClose(4001, 'kicked'), allOf(contains('4001'), contains('kicked')));
    });
  });

  group('heartbeat detects a silent drop', () {
    test('two missed pongs → drop reason + reconnect', () {
      fakeAsync((async) {
        final channels = <_FakeChannel>[];
        DaemonClient.channelFactory = (uri) {
          final c = _FakeChannel();
          channels.add(c);
          return c;
        };
        addTearDown(() => DaemonClient.channelFactory = WebSocketChannel.connect);

        final client = DaemonClient(
          payload: const PairingPayload(host: 'h', port: 1, token: 't'),
          sessionToken: 's',
        );
        client.connect();
        async.flushMicrotasks();
        // Deliver one frame so the client is CONNECTED (pong resets missed count).
        channels.first.inbound.add('{"type":"pong"}');
        async.flushMicrotasks();
        expect(client.state, ConnState.connected);

        // Now the daemon goes silent — no pong ever answered. Advance past three
        // 20s ping ticks: missed 1 → 2 → dead → reconnect.
        async.elapse(const Duration(seconds: 62));

        expect(client.stats.lastDropReason, contains('silent drop'));
        expect(client.stats.dropCount, greaterThanOrEqualTo(1));
        expect(channels.length, greaterThanOrEqualTo(2), reason: 'reconnected after the silent drop');

        client.dispose();
      });
    });
  });
}
