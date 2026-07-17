# App P2 slice 1 — the moment loop (task 8)

Flutter app: pair → connect → decide. Portrait-locked, pure Flutter widgets
(no Flame yet). 1955 theme from the approved style anchor.

## What's built

- **Pairing screen** — `mobile_scanner` QR scan → `POST /pair` → session token
  stored in `flutter_secure_storage`. Manual paste-payload fallback for
  emulators (no camera).
- **DaemonClient** — WS per event-model §WS: hello with replay-from-eventId,
  20 s heartbeat ping, reconnect with exponential backoff (500 ms → 15 s).
  Riverpod state: connection, event feed, pending decisions, autopilot.
- **The requisition overlay** — the product's heart. Document slides up from
  the bottom; 1955 layout (REQUISITION NN-X header, worker/class/flag chips);
  **diff core always visible** (monospace, scrollable, +green/−red tinting);
  swipe right = APPROVED green stamp slam, left = DENIED red; `HapticFeedback`
  + synthesized `stamp.wav`; commit threshold 110 px so a small drag doesn't
  decide; the decision posts to the daemon over WS. Rotation + colour wash
  track the drag.
- **Ambient screen** — approved workshop-floor still as backdrop, dry-template
  event feed as a manila "INCIDENT LOG" strip. NO Flame, NO sprites.
- **Autopilot banner** — when the daemon reports a permissive permission mode
  (acceptEdits/auto/dontAsk/bypassPermissions), a stamp-red banner: "WORKSHOP
  ON AUTOPILOT — DECISIONS BYPASS YOU". Daemon exposes mode in ws welcome,
  `/status`, and a live `session.mode` event.

## Evidence (headless — what a CI machine can prove)

- `flutter analyze`: **No issues found.**
- `flutter test`: **5/5 pass.**
  - `requisition_overlay_test.dart` — renders header + classification + the
    diff core (`echo cleared > victim.txt` visible); swipe left → `deny`;
    swipe right → `allow`; sub-threshold drag → no decision.
  - `daemon_loop_test.dart` — **the moment loop end-to-end in the app's real
    networking layer**: spawns the live Node daemon, `DaemonClient.pair` over
    HTTP, connects over WS, a simulated CC destructive `PreToolUse` is held,
    the client receives `decision.requested` and releases **deny**, and the
    held hook response is asserted `deny` (the tool would be blocked).

## The gate that needs hardware (owner: Rickard)

The task's gate is a screen recording: real phone on LAN, camera-scan the QR,
a real CC session's requisition arrives as a push-less overlay, swipe-deny
blocks the tool, with latency numbers. That needs a physical device + camera +
a real CC run — it can't be produced in this headless environment. The Dart
networking layer and the overlay interaction are both verified above; what
remains unproven here is only the on-device camera/render/haptics/audio and
LAN wifi path. Record it on a paired phone to close the gate.

## Run it yourself

```
# terminal 1 — daemon on a real project
cd daemon && node src/cli.ts --project /path/to/your/repo --port 47100
# terminal 2 — app on a device/emulator on the same LAN
cd app && flutter run
# scan the QR (or paste the "pair by hand" payload in manual mode)
```
