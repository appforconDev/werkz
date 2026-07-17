// Internal event envelope (event-model.md §1). The app tolerates unknown
// eventType values (renders as generic activity).
class WerkzEvent {
  final String eventId;
  final String timestamp;
  final String eventType;
  final String severity;
  final String? workerId;
  final Map<String, dynamic> payload;

  const WerkzEvent({
    required this.eventId,
    required this.timestamp,
    required this.eventType,
    required this.severity,
    required this.workerId,
    required this.payload,
  });

  factory WerkzEvent.fromJson(Map<String, dynamic> j) => WerkzEvent(
        eventId: j['eventId'] as String? ?? '',
        timestamp: j['timestamp'] as String? ?? '',
        eventType: j['eventType'] as String? ?? 'unknown',
        severity: j['severity'] as String? ?? 'info',
        workerId: j['workerId'] as String?,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
