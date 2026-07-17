// Integration: the app's real networking layer (DaemonClient) against a live
// daemon. Spawns the Node daemon, pairs, connects over WS, then a simulated CC
// PreToolUse (destructive) is held; the client releases DENY and we assert the
// held hook response is 'deny'. This is the moment loop minus the physical
// phone/CC — the gate's device video needs Rickard's hardware.
//
// Skipped automatically if `node` isn't on PATH.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:werkz_app/src/models/pairing_payload.dart';
import 'package:werkz_app/src/daemon/daemon_client.dart';

void main() {
  test('pair → connect → receive requisition → release deny → CC blocked', () async {
    final nodeOk = await _hasNode();
    if (!nodeOk) {
      // ignore: avoid_print
      print('SKIP: node not on PATH');
      return;
    }

    final daemonDir = Directory('${Directory.current.path}/../daemon');
    final projectDir = await Directory.systemTemp.createTemp('werkz-app-it-');
    const port = 47133;

    final proc = await Process.start(
      'node',
      ['src/cli.ts', '--project', projectDir.path, '--port', '$port'],
      workingDirectory: daemonDir.path,
      environment: {...Platform.environment, 'WERKZ_DEV': '1'},
    );
    String payloadB64 = '';
    final ready = Completer<void>();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.contains('pair by hand')) {
        payloadB64 = line.split(RegExp(r'\s+')).last;
        if (!ready.isCompleted) ready.complete();
      }
    });

    try {
      await ready.future.timeout(const Duration(seconds: 15));
      final payload = PairingPayload.tryDecode(payloadB64)!;

      final (session, pairErr) = await DaemonClient.pair(payload);
      expect(session, isNotNull, reason: 'pairing should succeed ($pairErr)');

      final client = DaemonClient(payload: payload, sessionToken: session!);
      final gotDecision = Completer<String>();
      client.onEvent = (e, replay) {
        if (e.eventType == 'decision.requested' && !replay) {
          final id = e.payload['decisionId'] as String;
          client.release(id, 'deny');
          if (!gotDecision.isCompleted) gotDecision.complete(id);
        }
      };
      client.connect();

      // Simulate CC issuing a destructive PreToolUse; the daemon holds this
      // request open until we release it.
      final held = HttpClient();
      final req = await held.postUrl(Uri.parse('http://${payload.host}:$port/pretooluse'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'hook_event_name': 'PreToolUse',
        'session_id': 'it-session',
        'tool_name': 'Bash',
        'tool_input': {'command': 'rm -rf build'},
        'permission_mode': 'default',
      })));
      final holdResponse = req.close();

      await gotDecision.future.timeout(const Duration(seconds: 10));
      final res = await holdResponse.timeout(const Duration(seconds: 10));
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final decision = (body['hookSpecificOutput'] as Map)['permissionDecision'];
      expect(decision, 'deny', reason: 'released deny must block the tool');

      client.dispose();
      held.close(force: true);
    } finally {
      proc.kill(ProcessSignal.sigkill);
      await projectDir.delete(recursive: true).catchError((_) => projectDir);
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}

Future<bool> _hasNode() async {
  try {
    final r = await Process.run('node', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
