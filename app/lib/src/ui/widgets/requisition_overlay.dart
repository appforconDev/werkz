import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/pending_decision.dart';
import '../theme.dart';
import 'diff_core.dart';

// THE REQUISITION — the product's heart (GDD §2.1). Rebuilt for feel (task 11.5):
//   - the card tracks the finger 1:1 and rotates around the grip point,
//   - a visual tipping threshold (stamp preview fades in as you pass it),
//   - release momentum: a flick completes, a slow release below threshold
//     springs back (Tinder as the reference bar),
//   - PAYOFF: on commit the CARD flies off-screen while a full-size
//     APPROVED/DENIED stamp SLAMS onto screen center (heavy haptic + sound),
//     holds ~600ms fully readable, then fades. The verdict is never truncated.
//   - `reducedEffects` skips the animation for accessibility.
class RequisitionOverlay extends StatefulWidget {
  final PendingDecision decision;
  final void Function(String decision) onDecide; // 'allow' | 'deny'
  final bool reducedEffects;

  const RequisitionOverlay({
    super.key,
    required this.decision,
    required this.onDecide,
    this.reducedEffects = false,
  });

  @override
  State<RequisitionOverlay> createState() => _RequisitionOverlayState();
}

class _RequisitionOverlayState extends State<RequisitionOverlay> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240))..forward();
  // Spring-back when released below threshold.
  late final AnimationController _spring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  // Card fly-off on commit.
  late final AnimationController _fly =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  // Independent stamp slam → hold → fade.
  late final AnimationController _stamp =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
  final _player = AudioPlayer();

  Offset _drag = Offset.zero;
  Offset _grip = Offset.zero; // where the finger grabbed, for rotation origin
  Size _cardSize = const Size(360, 480);
  String? _committing; // 'allow' | 'deny' once the verdict is decided
  Offset _flyTarget = Offset.zero;

  // Feel constants (tuned against Tinder).
  static const double _commitFraction = 0.26; // of screen width
  static const double _flickVelocity = 900; // px/s completes even under threshold
  static const double _previewStart = 44;
  static const double _maxAngle = 0.30; // rad at full-width drag

  @override
  void dispose() {
    _enter.dispose();
    _spring.dispose();
    _fly.dispose();
    _stamp.dispose();
    _player.dispose();
    super.dispose();
  }

  double get _commitThreshold => (_cardSize.width) * _commitFraction;

  void _onPanStart(DragStartDetails d) {
    if (_committing != null) return;
    _spring.stop();
    _grip = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_committing != null) return;
    setState(() => _drag += d.delta);
    if (_drag.dx.abs() > _commitThreshold) HapticFeedback.selectionClick();
  }

  void _onPanEnd(DragEndDetails d) {
    if (_committing != null) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    final past = _drag.dx.abs() > _commitThreshold;
    final flick = vx.abs() > _flickVelocity;
    if (past || flick) {
      final dir = (flick ? vx : _drag.dx) >= 0 ? 1 : -1;
      _commit(dir > 0 ? 'allow' : 'deny');
    } else {
      _springBack();
    }
  }

  void _springBack() {
    final from = _drag;
    _spring
      ..reset()
      ..addListener(() {
        final t = Curves.elasticOut.transform(_spring.value);
        setState(() => _drag = Offset.lerp(from, Offset.zero, t)!);
      });
    _spring.forward();
  }

  void _commit(String decision) {
    if (_committing != null) return;
    setState(() => _committing = decision);
    HapticFeedback.heavyImpact();
    unawaited(_player.play(AssetSource('sfx/stamp.wav')));
    // Both paths decide when the stamp animation completes (pump-friendly).
    _stamp.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDecide(decision);
    });

    if (widget.reducedEffects) {
      // Accessibility: a quick verdict, no fly-off or long hold.
      _stamp.duration = const Duration(milliseconds: 420);
      _stamp.forward(from: 0);
      return;
    }

    // Card flies off in the drag direction; the stamp does NOT travel with it.
    final dir = _drag.dx >= 0 ? 1.0 : -1.0;
    _flyTarget = Offset(dir * _cardSize.width * 1.6, _drag.dy);
    _fly.addListener(() => setState(() {}));
    unawaited(_fly.forward());
    _stamp.forward(from: 0); // slam-in / hold / fade sequence
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _card(constraints),
            if (_committing != null) Positioned.fill(child: IgnorePointer(child: _stampSlam(_committing!))),
          ],
        );
      },
    );
  }

  Widget _card(BoxConstraints constraints) {
    final d = widget.decision;
    // Current drag, blended toward the fly target during commit.
    final drag = _committing != null && !widget.reducedEffects
        ? Offset.lerp(_drag, _flyTarget, Curves.easeIn.transform(_fly.value))!
        : _drag;
    final angle = (drag.dx / (_cardSize.width == 0 ? 1 : _cardSize.width)) * _maxAngle;
    final center = Offset(_cardSize.width / 2, _cardSize.height / 2);

    final approving = drag.dx > 0;
    final previewT = ((drag.dx.abs() - _previewStart) / (_commitThreshold - _previewStart)).clamp(0.0, 1.0);
    final tint = previewT > 0
        ? (approving ? Werkz.approvalGreen : Werkz.stampRed).withValues(alpha: previewT * 0.45)
        : Colors.transparent;

    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final slide = (1 - _enter.value) * MediaQuery.of(context).size.height;
        return Transform.translate(offset: Offset(0, slide), child: child);
      },
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Transform.translate(
          offset: drag,
          child: Transform.rotate(
            angle: angle,
            origin: _grip - center, // rotate about the grip point
            child: _MeasureSize(
              onChange: (s) => _cardSize = s,
              child: _document(d, tint, previewT, approving),
            ),
          ),
        ),
      ),
    );
  }

  Widget _document(PendingDecision d, Color tint, double previewT, bool approving) {
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
          // Tipping-threshold preview: the stamp word ghosts in on the card as
          // you approach commit, so you feel the verdict before releasing.
          if (previewT > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: previewT,
                    child: Transform.rotate(
                      angle: -0.22,
                      child: _stampLabel(approving ? 'APPROVED' : 'DENIED',
                          approving ? Werkz.approvalGreen : Werkz.stampRed, 30),
                    ),
                  ),
                ),
              ),
            ),
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
        _chip('CLASS', d.decisionClass.toUpperCase(), color: destructive ? Werkz.stampRed : Werkz.gunmetal),
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
      children: const [
        Row(children: [
          Icon(Icons.chevron_left, color: Werkz.stampRed),
          Text('SWIPE — DENIED', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.stampRed, fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
        Row(children: [
          Text('APPROVED — SWIPE', style: TextStyle(fontFamily: Werkz.mono, color: Werkz.approvalGreen, fontWeight: FontWeight.bold, fontSize: 11)),
          Icon(Icons.chevron_right, color: Werkz.approvalGreen),
        ]),
      ],
    );
  }

  // Full-size verdict slammed onto SCREEN center, independent of the card.
  Widget _stampSlam(String decision) {
    final approve = decision == 'allow';
    final color = approve ? Werkz.approvalGreen : Werkz.stampRed;
    final label = approve ? 'APPROVED' : 'DENIED';
    return AnimatedBuilder(
      animation: _stamp,
      builder: (context, _) {
        final v = _stamp.value; // 0..1 over 1150ms
        // slam-in 0–0.26, hold 0.26–0.78, fade 0.78–1.0
        double scale, opacity;
        if (v < 0.26) {
          final t = Curves.easeOutBack.transform((v / 0.26).clamp(0.0, 1.0));
          scale = 2.6 - 1.6 * t;
          opacity = (v / 0.26).clamp(0.0, 1.0);
        } else if (v < 0.78) {
          scale = 1.0;
          opacity = 1.0;
        } else {
          scale = 1.0;
          opacity = (1 - (v - 0.78) / 0.22).clamp(0.0, 1.0);
        }
        // Reduced-effects path only drives _stamp to 0.26 then decides.
        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Transform.rotate(angle: -0.22, child: _stampLabel(label, color, 40)),
            ),
          ),
        );
      },
    );
  }

  Widget _stampLabel(String label, Color color, double fontSize) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.55, vertical: fontSize * 0.22),
      decoration: BoxDecoration(border: Border.all(color: color, width: 5)),
      child: Text(label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(fontFamily: Werkz.mono, color: color, fontWeight: FontWeight.w900, fontSize: fontSize, letterSpacing: 4)),
    );
  }
}

// Reports the rendered size of its child (for rotation origin + fly distance).
class _MeasureSize extends StatefulWidget {
  final Widget child;
  final void Function(Size) onChange;
  const _MeasureSize({required this.child, required this.onChange});
  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.size;
      if (s != null) widget.onChange(s);
    });
    return widget.child;
  }
}
