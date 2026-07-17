import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/pending_decision.dart';
import '../theme.dart';
import 'diff_core.dart';

// THE REQUISITION — the product's heart (GDD §2.1). A physical document slides
// up from the bottom; the diff core is always on screen; swipe right = APPROVED
// (green stamp slam), left = DENIED (red). Haptics + stamp sound. < 1s.
class RequisitionOverlay extends StatefulWidget {
  final PendingDecision decision;
  final void Function(String decision) onDecide; // 'allow' | 'deny'

  const RequisitionOverlay({super.key, required this.decision, required this.onDecide});

  @override
  State<RequisitionOverlay> createState() => _RequisitionOverlayState();
}

class _RequisitionOverlayState extends State<RequisitionOverlay> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  late final AnimationController _stamp =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  final _player = AudioPlayer();

  double _drag = 0; // horizontal drag offset
  String? _slamming; // 'allow' | 'deny' while the stamp animates

  static const _commitThreshold = 110.0;

  @override
  void dispose() {
    _enter.dispose();
    _stamp.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _commit(String decision) async {
    if (_slamming != null) return;
    setState(() => _slamming = decision);
    HapticFeedback.heavyImpact();
    unawaited(_player.play(AssetSource('sfx/stamp.wav')));
    await _stamp.forward(from: 0);
    widget.onDecide(decision);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _drag += d.delta.dx);
    if (_drag.abs() > _commitThreshold && _slamming == null) {
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_drag > _commitThreshold) {
      _commit('allow');
    } else if (_drag < -_commitThreshold) {
      _commit('deny');
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    final approving = _drag > 0;
    final tint = _drag.abs() > 40
        ? (approving ? Werkz.approvalGreen : Werkz.stampRed).withValues(alpha: (_drag.abs() / 260).clamp(0, 0.5))
        : Colors.transparent;

    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final slide = (1 - _enter.value) * MediaQuery.of(context).size.height;
        return Transform.translate(offset: Offset(0, slide), child: child);
      },
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Transform.translate(
          offset: Offset(_drag, 0),
          child: Transform.rotate(
            angle: _drag / 2600,
            child: _document(d, tint),
          ),
        ),
      ),
    );
  }

  Widget _document(PendingDecision d, Color tint) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      decoration: BoxDecoration(
        color: Werkz.cream,
        border: Border.all(color: Werkz.gunmetal, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(d),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _classificationRow(d),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: DiffCore(lines: d.diffCore),
                    ),
                    const SizedBox(height: 14),
                    _swipeHints(),
                  ],
                ),
              ),
            ],
          ),
          if (tint != Colors.transparent)
            Positioned.fill(child: IgnorePointer(child: ColoredBox(color: tint))),
          if (_slamming != null) Positioned.fill(child: _stampSlam(_slamming!)),
        ],
      ),
    );
  }

  Widget _header(PendingDecision d) {
    return Container(
      color: Werkz.manila,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Text('W', style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -2)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('REQUISITION ${d.requisitionNo}',
                    style: const TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)),
                const Text('DEPARTMENT OF AGENT OPERATIONS',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 9, color: Werkz.gunmetal, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _classificationRow(PendingDecision d) {
    final destructive = d.decisionClass == 'destructive';
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _chip('WORKER', d.workerLabel),
        _chip('CLASS', d.decisionClass.toUpperCase(),
            color: destructive ? Werkz.stampRed : Werkz.gunmetal),
        if (d.destructiveCategory != null) _chip('FLAG', d.destructiveCategory!.toUpperCase(), color: Werkz.stampRed),
        if (d.diffLines != null) _chip('LINES', '${d.diffLines}'),
        _chip('SUBJECT', d.toolCategory),
      ],
    );
  }

  Widget _chip(String k, String v, {Color color = Werkz.gunmetal}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: color), color: Werkz.carbon),
      child: Text('$k: $v',
          style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _swipeHints() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: const [
          Icon(Icons.chevron_left, color: Werkz.stampRed),
          Text('SWIPE — DENIED', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.stampRed, fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
        Row(children: const [
          Text('APPROVED — SWIPE', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.approvalGreen, fontWeight: FontWeight.bold, fontSize: 11)),
          Icon(Icons.chevron_right, color: Werkz.approvalGreen),
        ]),
      ],
    );
  }

  Widget _stampSlam(String decision) {
    final approve = decision == 'allow';
    final color = approve ? Werkz.approvalGreen : Werkz.stampRed;
    final label = approve ? 'APPROVED' : 'DENIED';
    return Center(
      child: AnimatedBuilder(
        animation: _stamp,
        builder: (context, _) {
          final t = Curves.easeOutBack.transform(_stamp.value);
          final scale = 2.4 - 1.4 * t;
          final opacity = _stamp.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Transform.rotate(
                angle: -0.22,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: color, width: 5)),
                  child: Text(label,
                      style: TextStyle(fontFamily: Werkz.mono, color: color, fontWeight: FontWeight.w900, fontSize: 34, letterSpacing: 4)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
