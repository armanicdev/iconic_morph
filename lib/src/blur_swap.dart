import 'package:flutter/widgets.dart';

import 'easing.dart';
import 'icon_effect.dart' show kIconStrokeWidth;
import 'icon_geometry.dart';
import 'motion.dart';

/// One glyph's share of a blur swap at a moment: how opaque it is, how
/// sharp ([focus] 1 = crisp, 0 = fully blurred), and its scale about the
/// box centre.
typedef BlurSwapPose = ({double alpha, double focus, double scale});

/// The timing law of a blur swap, on a 0..1 clock — shared by
/// [IconicBlurSwap] and by any host that paints its own glyphs (a stepper's
/// nodes, a procedural ring) and wants the same beat.
///
/// The outgoing glyph is gone by 55% of the clock; the incoming one starts
/// at 25%. The windows overlap so there is never an empty frame and never
/// two crisp glyphs. Each channel rides its own curve: focus and opacity
/// leave on an ease-in (the loss of focus accelerates, the way an eye
/// refocusing does) and arrive on [IconicEase.arrive]; the incoming SCALE
/// rides the spring ([IconicEase.snap]) so the new glyph lands with a hair
/// of overshoot — the snap that makes it feel like the tap did it.
abstract final class BlurSwapFrame {
  /// The outgoing glyph at clock [t]. [shrink] is the fraction of the box it
  /// gives up as it leaves.
  static BlurSwapPose out(double t, {double shrink = 0.2}) {
    final double w = (1 - t / 0.55).clamp(0.0, 1.0);
    // Ease-in on the loss: crisp for a beat, then gone.
    final double k = Curves.easeInCubic.transform(1 - w);
    return (alpha: 1 - k, focus: 1 - k, scale: 1 - shrink * k);
  }

  /// The incoming glyph at clock [t].
  static BlurSwapPose inn(double t, {double shrink = 0.2}) {
    final double w = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
    final double k = IconicEase.arrive.transform(w);
    final double s = IconicEase.snap.transform(w);
    return (alpha: k, focus: k, scale: 1 - shrink * (1 - s));
  }
}

/// A **blur cross-dissolve** between icons — the platform "replace" beat.
///
/// Show [icon]; change it and the glyph on screen softens, thins and shrinks
/// out of focus while the new one sharpens and springs into place over the
/// same centre. Nothing flies, nothing bends: for two icons that are not
/// siblings (a copy glyph and a check, a play and a pause) this reads as ONE
/// control changing state, where a path morph would draw a shape that means
/// nothing in between and a plain cross-fade shows two ghosts.
///
/// ```dart
/// IconicBlurSwap(copied ? MorphIcons.check : MorphIcons.copy, size: 18)
/// ```
///
/// Every change re-arms the swap from whatever is currently drawn, so a
/// double tap mid-swap re-points the dissolve rather than queueing it. The
/// blur is a mask filter on the glyph's own paint — no offscreen layer, no
/// image filter — so it costs what a blurred stroke costs and nothing more.
/// Geometry is cached by [IconGeometry]; a cold asset paints as soon as it
/// resolves. Reduced motion ([IconMotion.reduced]) snaps to the new icon.
/// The timing is [BlurSwapFrame].
class IconicBlurSwap extends StatefulWidget {
  const IconicBlurSwap(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = kIconStrokeWidth,
    this.duration = IconMotion.iconSwap,
    this.blur = 2.4,
    this.shrink = 0.2,
    this.semanticLabel,
  }) : assert(blur >= 0, 'blur is a sigma, in viewBox units'),
       assert(shrink >= 0 && shrink < 1, 'shrink is a fraction of the box');

  /// The icon to show — an asset path resolvable by [IconGeometry.load].
  /// Change it to play the swap.
  final String icon;

  /// The glyph box, in logical pixels.
  final double size;

  /// Ink; null → the ambient [DefaultTextStyle] colour.
  final Color? color;

  /// Stroke weight in viewBox units (the icon's own 24-box scale).
  final double strokeWidth;

  /// How long one swap takes.
  final Duration duration;

  /// Peak blur sigma, in viewBox units — how far out of focus a glyph is at
  /// the edge of its window. 2.4 on a 24-box reads as a soft loss of focus,
  /// not a smear.
  final double blur;

  /// How much the outgoing glyph shrinks as it leaves (and the incoming one
  /// springs up from), as a fraction of the box. 0 = a pure blur dissolve.
  final double shrink;

  final String? semanticLabel;

  @override
  State<IconicBlurSwap> createState() => _IconicBlurSwapState();
}

class _IconicBlurSwapState extends State<IconicBlurSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// What is leaving (null = nothing: first paint, or a settled swap).
  IconGeometry? _from;

  /// What is arriving / shown.
  IconGeometry? _to;
  String _toAsset = '';

  @override
  void initState() {
    super.initState();
    _toAsset = widget.icon;
    _resolve(widget.icon);
    _clock.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _from = null);
      }
    });
  }

  @override
  void didUpdateWidget(IconicBlurSwap old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _clock.duration = widget.duration;
    if (old.icon == widget.icon) return;
    // Re-arm from whatever is on screen: mid-swap that is the incoming glyph
    // at its current focus — the dissolve simply re-points.
    final bool reduce = IconMotion.reduced(context);
    setState(() {
      _from = reduce ? null : _to;
      _to = null;
      _toAsset = widget.icon;
    });
    _resolve(widget.icon);
    if (reduce) {
      _clock.value = 1;
    } else {
      _clock.forward(from: 0);
    }
  }

  void _resolve(String asset) {
    final cached = IconGeometry.peek(asset);
    if (cached != null) {
      _to = cached;
      return;
    }
    IconGeometry.load(asset).then((g) {
      if (!mounted || asset != _toAsset) return;
      setState(() => _to = g);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final Widget child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BlurSwapPainter(
          from: _from,
          to: _to,
          clock: _clock,
          color: color,
          strokeWidth: widget.strokeWidth,
          blur: widget.blur,
          shrink: widget.shrink,
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return child;
    return Semantics(label: label, image: true, child: child);
  }
}

/// Two glyphs over one centre, posed by [BlurSwapFrame].
class _BlurSwapPainter extends CustomPainter {
  _BlurSwapPainter({
    required this.from,
    required this.to,
    required this.clock,
    required this.color,
    required this.strokeWidth,
    required this.blur,
    required this.shrink,
  }) : super(repaint: clock);

  final IconGeometry? from;
  final IconGeometry? to;
  final Animation<double> clock;
  final Color color;
  final double strokeWidth;
  final double blur;
  final double shrink;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = from == null ? 1 : clock.value;
    if (from != null) {
      final pose = BlurSwapFrame.out(t, shrink: shrink);
      if (pose.alpha > 0) _glyph(canvas, size, from!, pose);
    }
    if (to != null) {
      final pose = BlurSwapFrame.inn(t, shrink: shrink);
      if (pose.alpha > 0) _glyph(canvas, size, to!, pose);
    }
  }

  void _glyph(Canvas canvas, Size size, IconGeometry geom, BlurSwapPose p) {
    final double s = size.shortestSide / geom.viewBox;
    final double sigma = blur * (1 - p.focus);
    final paint = Paint()
      ..color = color.withValues(alpha: color.a * p.alpha)
      ..style = geom.isFill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (sigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    final double half = geom.viewBox / 2;
    canvas.save();
    canvas.scale(s);
    canvas.translate(half, half);
    canvas.scale(p.scale);
    canvas.translate(-half, -half);
    canvas.drawPath(geom.path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlurSwapPainter old) =>
      old.from != from ||
      old.to != to ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.blur != blur ||
      old.shrink != shrink;
}
