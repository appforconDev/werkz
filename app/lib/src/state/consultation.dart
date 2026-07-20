import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

// Advisor Consultation (task 39): chat WITH the Advisor to PLAN a job before
// dispatch. Zero keys — the daemon spawns the user's own claude in plan mode
// (read + reason, never write/run). This holds the on-phone view of the exchange.

enum ConsultRole { operator, advisor }

class ConsultTurn {
  final ConsultRole role;
  final String text;
  const ConsultTurn(this.role, this.text);
}

class ConsultationState {
  final String? sessionId;
  final List<ConsultTurn> turns;
  final bool starting;  // opening a session
  final bool waiting;   // the Advisor is drafting a reply (room shows it working)
  final String? error;  // loud-but-kind failure (Advisor unavailable / too slow)
  const ConsultationState({
    this.sessionId,
    this.turns = const [],
    this.starting = false,
    this.waiting = false,
    this.error,
  });

  /// The latest Advisor reply — the plan the operator can dispatch (null if none).
  String? get latestPlan {
    for (final t in turns.reversed) {
      if (t.role == ConsultRole.advisor) return t.text;
    }
    return null;
  }

  ConsultationState copyWith({
    String? sessionId,
    List<ConsultTurn>? turns,
    bool? starting,
    bool? waiting,
    String? error,
    bool clearError = false,
  }) =>
      ConsultationState(
        sessionId: sessionId ?? this.sessionId,
        turns: turns ?? this.turns,
        starting: starting ?? this.starting,
        waiting: waiting ?? this.waiting,
        error: clearError ? null : (error ?? this.error),
      );
}

final consultationProvider =
    NotifierProvider<ConsultationController, ConsultationState>(ConsultationController.new);

class ConsultationController extends Notifier<ConsultationState> {
  @override
  ConsultationState build() => const ConsultationState();

  /// Open a consultation session (idempotent — reuses an existing one).
  Future<void> ensureStarted() async {
    if (state.sessionId != null || state.starting) return;
    final c = ref.read(workshopProvider.notifier).client;
    if (c == null) {
      state = state.copyWith(error: 'Advisor unavailable — not connected to the workshop.');
      return;
    }
    state = state.copyWith(starting: true, clearError: true);
    final (id, err) = await c.consultStart();
    state = state.copyWith(starting: false, sessionId: id, error: err);
  }

  /// Send one memo to the Advisor; the reply appends when it arrives. While the
  /// Advisor drafts, [waiting] is true (the room shows it working, not a spinner).
  Future<void> send(String message) async {
    final text = message.trim();
    if (text.isEmpty || state.waiting) return;
    var sid = state.sessionId;
    if (sid == null) {
      await ensureStarted();
      sid = state.sessionId;
      if (sid == null) return; // start failed → error already set
    }
    final c = ref.read(workshopProvider.notifier).client;
    if (c == null) {
      state = state.copyWith(error: 'Advisor unavailable — not connected.');
      return;
    }
    state = state.copyWith(
      turns: [...state.turns, ConsultTurn(ConsultRole.operator, text)],
      waiting: true,
      clearError: true,
    );
    final (reply, err) = await c.consultSend(sid, text);
    if (reply != null) {
      state = state.copyWith(
        turns: [...state.turns, ConsultTurn(ConsultRole.advisor, reply)],
        waiting: false,
      );
    } else {
      state = state.copyWith(waiting: false, error: err ?? 'The Advisor could not respond.');
    }
  }

  /// Close the current consultation view (keeps the daemon session for reconnect).
  void reset() => state = const ConsultationState();
}
