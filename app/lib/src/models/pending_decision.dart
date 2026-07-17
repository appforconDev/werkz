// A game-safe pending decision — the requisition (event-model.md §3, §4.3).
// Only categories/counts, never raw command/content.
class PendingDecision {
  final String decisionId;
  final String decisionClass;
  final String room;
  final String toolCategory;
  final String? destructiveCategory;
  final int? diffLines;
  final String openedAt;
  final String? workerId;
  // Device-zone only (event-model §4.3): [{sign, text}] shown in the overlay.
  final List<Map<String, dynamic>> diffCore;

  const PendingDecision({
    required this.decisionId,
    required this.decisionClass,
    required this.room,
    required this.toolCategory,
    required this.destructiveCategory,
    required this.diffLines,
    required this.openedAt,
    this.workerId,
    this.diffCore = const [],
  });

  factory PendingDecision.fromJson(Map<String, dynamic> j) => PendingDecision(
        decisionId: j['decisionId'] as String,
        decisionClass: j['decisionClass'] as String? ?? 'unknown',
        room: j['room'] as String? ?? 'workshop-floor',
        toolCategory: j['toolCategory'] as String? ?? 'Tool',
        destructiveCategory: j['destructiveCategory'] as String?,
        diffLines: j['diffLines'] as int?,
        openedAt: j['openedAt'] as String? ?? '',
        workerId: j['workerId'] as String?,
        diffCore: ((j['diffCore'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
      );

  String get workerLabel => workerId ?? 'WX-7A19';

  // Requisition number, deterministic from the id tail — pure decoration.
  String get requisitionNo {
    final tail = decisionId.replaceAll('-', '');
    final n = tail.isEmpty ? 0 : int.parse(tail.substring(tail.length - 3), radix: 16) % 100;
    final letter = String.fromCharCode(65 + (tail.isEmpty ? 0 : tail.codeUnitAt(0) % 26));
    return '${n.toString().padLeft(2, '0')}-$letter';
  }
}
