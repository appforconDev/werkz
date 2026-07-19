import 'package:flutter/material.dart';
import '../theme.dart';

// Task 23B: the work-order COMPLETION REPORT — the agent's final answer,
// delivered to the phone and read like a filed 1955 document (typed page on
// cream paper, manila letterhead, FILED stamp), not a chat bubble. Opened from
// the completed work-order toast and from job.completed lines in the LOG.
// Static content → goldenable.

void showWorkReport(
  BuildContext context, {
  required String report,
  String? summary, // Haiku one-liner (narration.ready) when it has arrived
  int? turns,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) =>
          WorkReportSheet(report: report, summary: summary, turns: turns, scrollController: scrollController),
    ),
  );
}

class WorkReportSheet extends StatelessWidget {
  final String report;
  final String? summary;
  final int? turns;
  final ScrollController? scrollController;
  const WorkReportSheet({super.key, required this.report, this.summary, this.turns, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Werkz.manila,
        border: Border(top: BorderSide(color: Werkz.gunmetal, width: 2)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Werkz.gunmetal, borderRadius: BorderRadius.circular(2))),
          ),
          // Letterhead: form number left, FILED stamp right.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 16, color: Werkz.machine),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('COMPLETION REPORT — FORM 9-R',
                      style: TextStyle(
                          fontFamily: Werkz.mono, fontWeight: FontWeight.w900,
                          letterSpacing: 2, fontSize: 13, color: Werkz.machine)),
                ),
                Transform.rotate(
                  angle: -0.10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: Werkz.approvalGreen, width: 2)),
                    child: const Text('FILED',
                        style: TextStyle(
                            fontFamily: Werkz.mono, fontWeight: FontWeight.w900,
                            fontSize: 12, letterSpacing: 3, color: Werkz.approvalGreen)),
                  ),
                ),
              ],
            ),
          ),
          if (turns != null)
            Padding(
              padding: const EdgeInsets.only(left: 38, right: 14, top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('LABOR EXPENDED: $turns TURNS',
                    style: const TextStyle(fontFamily: Werkz.mono, fontSize: 10, letterSpacing: 1, color: Werkz.gunmetal)),
              ),
            ),
          const Divider(color: Werkz.gunmetal, height: 14),
          // Foreman's summary line — the Haiku narration when present, else the
          // dry stock line. Dry tone either way; never a chat voice.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('» ${summary ?? 'Work order executed. Findings attached.'}',
                  style: const TextStyle(
                      fontFamily: Werkz.mono, fontSize: 12,
                      fontStyle: FontStyle.italic, color: Werkz.machine)),
            ),
          ),
          // The typed report page.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Werkz.cream,
                  border: Border.all(color: Werkz.gunmetal, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(report,
                      style: const TextStyle(fontFamily: Werkz.mono, fontSize: 12, height: 1.45, color: Werkz.oil)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
