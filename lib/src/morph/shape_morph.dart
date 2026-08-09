import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../animated_icon.dart' show IconicAnimatedIconController;
import '../easing.dart';
import '../icon_effect.dart' show kIconStrokeWidth;
import '../icon_geometry.dart';
import '../icon_image.dart';
import '../motion.dart';
import '../stroke_taper.dart';
import 'path_morph.dart';

/// The SHAPE morph — the engine's second morph instrument, for icons that are
/// SIBLINGS rather than strangers.
///
/// [IconicMorph] (the worm) exists for icons that share nothing: one hero line
/// flies a flight path while the rest of the target draws itself on. Between
/// two icons that share most of their drawing — a face-id frame whose centre
/// mark is the only thing that changes, a status glyph with interchangeable
/// badges — the worm is the wrong instrument: it retracts and re-draws the
/// shared chrome around a tiny hop, and the transition reads as the icon
/// flickering apart.
///
/// The shape morph does what a sibling swap actually calls for:
///
///   1. **Shared contours hold still.** Any contour present in BOTH icons
///      (detected geometrically, no configuration) is drawn once and never
///      animated.
///   2. **Paired contours BECOME each other** — resampled to a common point
///      count, direction-aligned, and point-lerped, so the line itself bends
///      from one feature into the other at a constant stroke weight.
///   3. **Everything unpaired** pen-retracts out / draws on under the trim-end
///      laws ([StrokeTaper] — no terminal-dot frames, no opacity pops).
///   4. **Ink travels with the geometry**: the still chrome and the morphing
///      shapes each lerp between a begin and an end colour on the same eased
///      clock, so a verdict can arrive in its own colour without a snap.
///
/// Pure geometry lives in [ShapeMorphGeometry] (VM-testable), painting in
/// [ShapeMorphPainter] (drive it with your own controller), and
/// [IconicShapeMorph] is the drop-in widget.
@immutable
class ShapeMorphSpec {
  const ShapeMorphSpec({
    this.pairs = const [],
    this.autoPair = true,
    this.samples = 48,
    this.stillTolerance = 0.25,
    this.outShare = 0.55,
    this.inStart = 0.45,
    this.stagger = 0.08,
    this.exitFadeStart = 0.6,
    this.curve = IconicEase.snap,
    this.colorCurve,
  })  : assert(samples >= 8, 'too few samples to read as a smooth line'),
        assert(outShare > 0 && outShare <= 1),
        assert(inStart >= 0 && inStart < 1);

  /// Explicit feature pairings, as `(fromAnchor, toAnchor)` viewBox points —
  /// each anchor resolves to the remaining contour whose centroid is nearest
  /// (order-independent, the same robustness argument as
  /// `IconMorphPlan.heroAnchor`). Use this when the choreography is a design
  /// decision — "the smile becomes the dot" — that no heuristic should get to
  /// overrule. Anchors that double-book a contour are skipped.
  final List<(Offset, Offset)> pairs;

  /// After [pairs], greedily pair the remaining contours by similarity
  /// (arc-length difference + centroid distance). True by default so two
  /// sibling icons morph reasonably with a bare spec; set false to make every
  /// unlisted contour exit/enter instead.
  final bool autoPair;

  /// Points per morphing pair — enough that a bending line stays silk at hero
  /// sizes.
  final int samples;

  /// Max point deviation (viewBox units) for two contours to count as THE SAME
  /// contour (the still chrome). A quarter unit on a 24 box forgives float
  /// noise without ever matching genuinely different features.
  final double stillTolerance;

  /// Exits clear inside the first [outShare] of the eased clock; enters draw
  /// over the last `1 - `[inStart]. The default overlap keeps the beat one
  /// gesture rather than two queued animations.
  final double outShare;
  final double inStart;

  /// Per-contour cascade inside the exit / enter windows.
  final double stagger;

  /// Where inside a retract its dissolve begins (see [StrokeTaper.exitAlpha]).
  final double exitFadeStart;

  /// The master clock everything reads — geometry, exits, enters, and (unless
  /// [colorCurve] says otherwise) ink. Defaults to [IconicEase.snap], the
  /// critically-damped spring: a verdict lands with genuine launch velocity
  /// and settles on an exponential tail. Hand it [IconicEase.glide] for the
  /// calm symmetric profile, [IconicEase.flight] for the worm's launch, or any
  /// [Curve] — including a tuned [IconicSpringCurve].
  final Curve curve;

  /// The INK's own clock, when colour should not ride the geometry's. Null
  /// (default) follows [curve] exactly — one gesture, one clock. Set it when
  /// the colour story should lead (e.g. [Curves.easeOutCubic] announces the
  /// verdict ink while the line is still bending) or trail the shapes.
  final Curve? colorCurve;

  @override
  bool operator ==(Object other) =>
      other is ShapeMorphSpec &&
      _pairsEqual(other.pairs, pairs) &&
      other.autoPair == autoPair &&
      other.samples == samples &&
      other.stillTolerance == stillTolerance &&
      other.outShare == outShare &&
      other.inStart == inStart &&
      other.stagger == stagger &&
      other.exitFadeStart == exitFadeStart &&
      other.curve == curve &&
      other.colorCurve == colorCurve;

  static bool _pairsEqual(
    List<(Offset, Offset)> a,
    List<(Offset, Offset)> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        ...pairs,
        autoPair,
        samples,
        stillTolerance,
        outShare,
        inStart,
        stagger,
        exitFadeStart,
        curve,
        colorCurve,
      ]);
}

/// One paired feature: same-count, direction-aligned point lists — the line
/// that bends from [from] into [to].
@immutable
class ShapeMorphPair {
  const ShapeMorphPair(this.from, this.to);

  final List<Offset> from;
  final List<Offset> to;
}

/// The precomputed shape-morph: still chrome, bending pairs, and the contours
/// that leave or arrive. Pure and immutable — build once per (from, to, spec)
/// and hand it to a [ShapeMorphPainter]; never rebuild per frame.
@immutable
class ShapeMorphGeometry {
  const ShapeMorphGeometry._({
    required this.still,
    required this.pairs,
    required this.exits,
    required this.enters,
    required this.viewBox,
  });

  /// Contours present in BOTH icons, as one prebuilt path (drawn from [to]'s
  /// copy). Never animated.
  final Path still;

  /// The features that become each other.
  final List<ShapeMorphPair> pairs;

  /// [from]-only contours — they pen-retract out over the first half.
  final List<IconContour> exits;

  /// [to]-only contours — they draw on over the second half.
  final List<IconContour> enters;

  final double viewBox;

  static ShapeMorphGeometry build(
    IconGeometry from,
    IconGeometry to,
    ShapeMorphSpec spec,
  ) {
    final fromLeft = List.of(from.contours);
    final toLeft = List.of(to.contours);

    // 1 — the still chrome: greedy one-to-one matching of identical contours.
    final still = Path();
    for (var i = fromLeft.length - 1; i >= 0; i--) {
      final match = _identicalIn(fromLeft[i], toLeft, spec.stillTolerance);
      if (match == null) continue;
      still.addPath(match.polygon, Offset.zero);
      toLeft.remove(match);
      fromLeft.removeAt(i);
    }

    // 2 — explicit pairs, each anchor resolving to the nearest remaining
    // contour. A double-booked contour is a spec bug; skip the duplicate
    // rather than bending one feature two ways at once.
    final pairs = <ShapeMorphPair>[];
    void pair(IconContour src, IconContour dst) {
      final srcPts = PathMorph.resampleContour(src, spec.samples);
      final dstPts = PathMorph.alignTo(
        srcPts,
        PathMorph.resampleContour(dst, spec.samples),
      );
      pairs.add(ShapeMorphPair(srcPts, dstPts));
      fromLeft.remove(src);
      toLeft.remove(dst);
    }

    for (final (a, b) in spec.pairs) {
      final src = _nearest(fromLeft, a);
      final dst = _nearest(toLeft, b);
      if (src == null || dst == null) continue;
      pair(src, dst);
    }

    // 3 — auto-pair the remainder by similarity: longest target first (the
    // dominant feature deserves the best partner), scored by arc-length
    // difference + centroid distance.
    if (spec.autoPair) {
      final targets = List.of(toLeft)
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final dst in targets) {
        if (fromLeft.isEmpty) break;
        IconContour? best;
        var bestScore = double.infinity;
        final dstCentroid = PathMorph.centroid(dst.points);
        for (final src in fromLeft) {
          final score = (src.length - dst.length).abs() +
              0.5 * (PathMorph.centroid(src.points) - dstCentroid).distance;
          if (score < bestScore) {
            bestScore = score;
            best = src;
          }
        }
        pair(best!, dst);
      }
    }

    return ShapeMorphGeometry._(
      still: still,
      pairs: pairs,
      exits: fromLeft,
      enters: toLeft,
      viewBox: from.viewBox,
    );
  }

  /// The contour in [candidates] that IS [c] (max sampled deviation under
  /// [tolerance]), or null. Both are resampled to one modest count first so
  /// the comparison is sampling-independent.
  static IconContour? _identicalIn(
    IconContour c,
    List<IconContour> candidates,
    double tolerance,
  ) {
    const probe = 24;
    final a = PathMorph.resampleContour(c, probe);
    for (final other in candidates) {
      if ((other.length - c.length).abs() > tolerance * probe) continue;
      final b = PathMorph.alignTo(a, PathMorph.resampleContour(other, probe));
      var maxD = 0.0;
      for (var i = 0; i < probe; i++) {
        maxD = math.max(maxD, (a[i] - b[i]).distance);
        if (maxD > tolerance) break;
      }
      if (maxD <= tolerance) return other;
    }
    return null;
  }

  static IconContour? _nearest(List<IconContour> cs, Offset anchor) {
    IconContour? best;
    var bestD = double.infinity;
    for (final c in cs) {
      final d = (PathMorph.centroid(c.points) - anchor).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }
}

/// Paints a [ShapeMorphGeometry] at the clock's current value: still chrome
/// with its ink lerping, pairs bending point-for-point with theirs, exits and
/// enters trimming under the [StrokeTaper] laws. Drive it with any
/// `Animation<double>` — an [IconicShapeMorph] for the drop-in case, or your
/// own controller when the morph is one voice inside a larger stateful glyph.
class ShapeMorphPainter extends CustomPainter {
  ShapeMorphPainter({
    required this.geometry,
    required this.animation,
    required this.color,
    Color? colorEnd,
    Color? chromeColor,
    Color? chromeColorEnd,
    this.spec = const ShapeMorphSpec(),
    this.strokeWidth = kIconStrokeWidth,
  })  : colorEnd = colorEnd ?? color,
        chromeColor = chromeColor ?? color,
        chromeColorEnd = chromeColorEnd ?? colorEnd ?? color,
        super(repaint: animation);

  final ShapeMorphGeometry geometry;
  final Animation<double> animation;

  /// Ink of the MORPHING shapes (pairs + exits + enters) at the start / end.
  final Color color;
  final Color colorEnd;

  /// Ink of the STILL chrome at the start / end. Defaults follow [color] /
  /// [colorEnd] — one-colour icons need nothing extra.
  final Color chromeColor;
  final Color chromeColorEnd;

  /// Timing knobs are read from the same spec that built [geometry].
  final ShapeMorphSpec spec;

  final double strokeWidth;

  // Scratch buffer for the lerped pair points — refilled per pair per frame so
  // a 120 Hz morph doesn't allocate. Every pair is spec.samples long.
  late final List<Offset> _lerpBuf = List<Offset>.filled(
    geometry.pairs.isEmpty ? 0 : geometry.pairs.first.from.length,
    Offset.zero,
  );

  Paint? _paint;
  Paint get _stroke => _paint ??= (Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true);

  /// Contour [i] of [n]'s local progress inside a half-window, cascaded.
  double _local(double t, int i, int n) {
    if (n <= 1) return t.clamp(0.0, 1.0);
    final width = 1 - (n - 1) * spec.stagger;
    return ((t - i * spec.stagger) / width).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / geometry.viewBox;
    final paint = _stroke;
    canvas.save();
    canvas.scale(s);

    // ONE master clock for all geometry — exits, enters, bending pairs. Ink
    // follows it too unless the spec gives colour its own profile; two clocks
    // for the same DISTANCE argue, but colour leading geometry is a voice.
    final t = animation.value.clamp(0.0, 1.0);
    final move = spec.curve.transform(t);
    final ink = spec.colorCurve == null ? move : spec.colorCurve!.transform(t);

    // The still chrome — never re-drawn, ink walking with the colour clock.
    paint.color = Color.lerp(chromeColor, chromeColorEnd, ink)!;
    canvas.drawPath(geometry.still, paint);

    // Paired shapes — the feature BECOMES its partner.
    paint.color = Color.lerp(color, colorEnd, ink)!;
    for (final p in geometry.pairs) {
      for (var i = 0; i < p.from.length; i++) {
        _lerpBuf[i] = Offset.lerp(p.from[i], p.to[i], move)!;
      }
      canvas.drawPath(Path()..addPolygon(_lerpBuf, false), paint);
    }

    // Exits retract through the first half in their OUTGOING ink, dissolving
    // before their dot horizon.
    final outT = (move / spec.outShare).clamp(0.0, 1.0);
    if (outT < 1) {
      for (var i = 0; i < geometry.exits.length; i++) {
        final c = geometry.exits[i];
        final local = _local(outT, i, geometry.exits.length);
        final alpha = StrokeTaper.exitAlpha(
          local,
          spec.exitFadeStart,
          c.length,
          strokeWidth,
        );
        if (alpha <= 0 || local >= 1) continue;
        paint.color = color.withValues(alpha: color.a * alpha);
        canvas.drawPath(PathMorph.trimmedRange(c, 0, 1 - local), paint);
      }
    }

    // Enters draw on over the second half in their ARRIVING ink, emerging
    // from transparent.
    final inT = ((move - spec.inStart) / (1 - spec.inStart)).clamp(0.0, 1.0);
    if (inT > 0) {
      for (var i = 0; i < geometry.enters.length; i++) {
        final c = geometry.enters[i];
        final local = _local(inT, i, geometry.enters.length);
        if (local <= 0) continue;
        final alpha = StrokeTaper.emerge(local, StrokeTaper.kEndFade);
        if (alpha <= 0) continue;
        paint.color = colorEnd.withValues(alpha: colorEnd.a * alpha);
        canvas.drawPath(PathMorph.trimmedContour(c, local), paint);
      }
    }

    canvas.restore();
  }

  // Per-tick invalidation is owned by super(repaint:) — a NEW painter means a
  // genuine rebuild; compare immutable inputs (identity) + the listenable.
  @override
  bool shouldRepaint(ShapeMorphPainter old) =>
      old.color != color ||
      old.colorEnd != colorEnd ||
      old.chromeColor != chromeColor ||
      old.chromeColorEnd != chromeColorEnd ||
      old.strokeWidth != strokeWidth ||
      old.spec != spec ||
      !identical(old.geometry, geometry) ||
      old.animation != animation;
}

/// Drop-in widget: morph sibling icon [from] into [to] as a SHAPE morph. Rests
/// on [from]; plays once on load (or via [controller]); reduced motion settles
/// straight on [to]. For a morph that lives inside a larger stateful glyph
/// (several destinations, bespoke rest states), drive [ShapeMorphPainter] with
/// your own controller instead — this widget is the one-shot convenience.
class IconicShapeMorph extends StatefulWidget {
  const IconicShapeMorph(
    this.from,
    this.to, {
    super.key,
    this.spec = const ShapeMorphSpec(),
    this.size = 24,
    this.color,
    this.colorEnd,
    this.chromeColor,
    this.chromeColorEnd,
    this.duration = IconMotion.shapeMorph,
    this.autoplay = true,
    this.controller,
    this.semanticLabel,
  });

  /// Source / target SVG asset paths (e.g. `MorphIcons.*`).
  final String from;
  final String to;

  final ShapeMorphSpec spec;
  final double size;

  /// Morphing-shape ink at start / end. Null [color] resolves to the ambient
  /// [DefaultTextStyle] color; null [colorEnd] holds [color].
  final Color? color;
  final Color? colorEnd;

  /// Still-chrome ink at start / end; defaults follow [color] / [colorEnd].
  final Color? chromeColor;
  final Color? chromeColorEnd;

  final Duration duration;

  /// Play automatically once both geometries are ready. When false it rests
  /// on [from] until [controller]`.play()`.
  final bool autoplay;

  /// Optional external trigger (the shared animated-icon handle): `play()`
  /// morphs from→to, `stop()` settles back on the source.
  final IconicAnimatedIconController? controller;

  final String? semanticLabel;

  @override
  State<IconicShapeMorph> createState() => _IconicShapeMorphState();
}

class _IconicShapeMorphState extends State<IconicShapeMorph>
    with SingleTickerProviderStateMixin {
  // Eager, never lazy — a Ticker first touched during dispose throws (see
  // IconicMorph's note on the deactivated-ancestor crash).
  late final AnimationController _ac;
  ShapeMorphGeometry? _geom;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: widget.duration);
    widget.controller?.addListener(_onController);
    _load();
  }

  Future<void> _load() async {
    final from = await IconGeometry.load(widget.from);
    final to = await IconGeometry.load(widget.to);
    if (!mounted) return;
    setState(() {
      _geom = ShapeMorphGeometry.build(from, to, widget.spec);
    });
  }

  void _onController() {
    if (!mounted) return;
    if (widget.controller!.stopRequested) {
      _ac.animateBack(0, duration: widget.duration);
    } else {
      _ac.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(IconicShapeMorph old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
    if (old.from != widget.from ||
        old.to != widget.to ||
        old.spec != widget.spec) {
      _geom = null;
      _kicked = false;
      _ac.value = 0;
      _load();
    }
    _ac.duration = widget.duration;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = widget.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final geom = _geom;

    // Geometry still resolving — a static frame of the source, no flash.
    if (geom == null) {
      return IconImage.asset(
        widget.from,
        size: widget.size,
        color: color,
        semanticLabel: widget.semanticLabel,
      );
    }

    if (reduce) {
      // Motion is replaced, never sped up: rest straight on the target frame.
      _ac.value = 1;
    } else if (widget.autoplay && !_kicked) {
      _kicked = true;
      _ac.forward(from: 0);
    }

    final child = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: ShapeMorphPainter(
          geometry: geom,
          animation: _ac,
          color: color,
          colorEnd: widget.colorEnd,
          chromeColor: widget.chromeColor,
          chromeColorEnd: widget.chromeColorEnd,
          spec: widget.spec,
        ),
      ),
    );

    if (widget.semanticLabel == null) return child;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: ExcludeSemantics(child: child),
    );
  }
}
