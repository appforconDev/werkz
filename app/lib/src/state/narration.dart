import '../models/werkz_event.dart';

// Dry-log templates (event-model.md §4.1 routine class). No LLM yet — this is
// the deterministic P2 stand-in: turn an event into one dry bureaucratic line.
// Never surfaces raw repo strings (§4.3) — only categories from the payload.
String narrate(WerkzEvent e) {
  final p = e.payload;
  final room = p['room'] as String?;
  final tool = p['toolCategory'] as String?;
  switch (e.eventType) {
    case 'task.started':
      return switch (room) {
        'archive' => 'Records clerk pulls a folder.',
        'test-workshop' => 'Test bench powers up.',
        _ => 'Worker takes station${tool != null ? ' ($tool)' : ''}.',
      };
    case 'decision.requested':
      final cls = p['decisionClass'];
      final cat = p['destructiveCategory'];
      return 'Requisition filed — $cls${cat != null ? ' ($cat)' : ''}. Awaiting stamp.';
    case 'decision.approved':
      return 'Requisition APPROVED. Filed.';
    case 'decision.denied':
      return 'Requisition DENIED. Returned to sender.';
    case 'decision.superseded':
      return 'Requisition withdrawn — the terminal handled it.';
    case 'session.mode':
      return p['autopilot'] == true
          ? 'Notice: workshop switched to autopilot.'
          : 'Notice: manual oversight restored.';
    default:
      return e.eventType;
  }
}
