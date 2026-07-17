// Preflight diagnostics mirror (daemon src/preflight/index.ts, task 13 B). The
// daemon checks its own environment and ships the result on the WS welcome and
// /status; the app raises an actionable banner when anything fails. Game-safe:
// ids/labels/short details only.
class PreflightCheck {
  final String id; // claude | hook | node | port
  final String label;
  final bool ok;
  final String detail;
  final String? hint;

  const PreflightCheck({
    required this.id,
    required this.label,
    required this.ok,
    required this.detail,
    this.hint,
  });

  factory PreflightCheck.fromJson(Map<String, dynamic> j) => PreflightCheck(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        ok: j['ok'] == true,
        detail: j['detail'] as String? ?? '',
        hint: j['hint'] as String?,
      );
}

class Preflight {
  final bool ok;
  final List<PreflightCheck> checks;

  const Preflight({required this.ok, this.checks = const []});

  List<PreflightCheck> get failures => checks.where((c) => !c.ok).toList();

  factory Preflight.fromJson(Map<String, dynamic> j) => Preflight(
        ok: j['ok'] == true,
        checks: ((j['checks'] as List?) ?? const [])
            .map((e) => PreflightCheck.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
