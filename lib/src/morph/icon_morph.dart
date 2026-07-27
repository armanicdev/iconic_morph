import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../icon_image.dart';
import '../motion.dart';

import '../icon_effect.dart';
import '../icon_geometry.dart';
import '../animated_icon.dart';
import '../projection_3d.dart';
import '../stroke_taper.dart';
import 'morph_geometry.dart';
import 'morph_plan.dart';
import 'path_morph.dart';

/// Morphs one icon into another by re-drawing path geometry per frame — no Rive,
/// no Lottie, no new assets, the same engine as [IconicAnimatedIcon]. Pass [from]
/// and [to] asset paths and an optional [plan] to tune the flight.
///
/// Shows a static [IconImage] of [from] until both geometries resolve, so the
/// first frame is never blank. Reduced-motion settles directly to [to].
///
/// The morph recipe lives in [IconMorphPlan], the precomputed geometry in
/// [MorphGeometry]; this class is the widget + painter.
class IconicMorph extends StatefulWidget {
  const IconicMorph(
    this.from,
    this.to, {
    super.key,
    this.plan = const IconMorphPlan(),
    this.size = 24,
    this.color,
    this.controller,
    this.autoplay = true,
    this.reverse = false,
    this.timeScale = 1,
    this.scrub,
    this.semanticLabel,
    this.debugTangents = false,
    this.motionBlur = false,
  });

  /// Source SVG asset path, e.g. `MorphIcons.user`.
  final String from;

  /// Target SVG asset path, e.g. `MorphIcons.face`.
  final String to;

  final IconMorphPlan plan;
  final double size;

  /// Tint color. Null resolves to the ambient [DefaultTextStyle] color.
  final Color? color;

  /// Optional external trigger (reuses the animated-icon handle): [play] morphs
  /// from→to, [stop] settles back to the source.
  final IconicAnimatedIconController? controller;

  /// Morph automatically once both geometries are ready. When false it rests on
  /// the source until [controller.play].
  final bool autoplay;

  /// Play the SAME [from]→[to] morph TIME-REVERSED: the controller runs 1→0
  /// instead of 0→1, so every frame is the forward morph at `(1 - t)`. The shown
  /// pair stays the forward pair (so geometry + [plan] are identical), but it now
  /// reads visually as [to]→[from]. This is how a "go back" transition reuses its
  /// forward morph exactly, traversed backward — no bespoke reverse plan, no
  /// asymmetry. Settled/rest frames flip accordingly (rest = the [to] frame).
  final bool reverse;

  /// Stretches the morph duration (1 = real time, 6 = 6× slow motion) — lets a
  /// gallery inspect the wander frame by frame without changing the plan.
  final double timeScale;

  /// Scrub override (0..1). When non-null the morph holds this exact frame
  /// instead of playing — drives a draggable timeline. Disables autoplay.
  final double? scrub;

  final String? semanticLabel;

  /// Debug overlay: draw a red line **20px ahead** of the worm's head (along its
  /// forward tangent — where the head is heading) and a blue line **20px before**
  /// its tail (backward — where the tail trails from), plus a marker dot at each.
  /// Lets us see the head/tail directions the flight path is being asked to follow.
  final bool debugTangents;

  /// Cheap **motion blur** on the travelling worm: when true, the worm stroke gets
  /// a Gaussian [MaskFilter] whose sigma rises to a peak mid-flight (when the head
  /// is moving fastest) and is 0 at rest at both ends — so it reads as speed blur
  /// without smearing the settled glyph. One paint property, ~free; off by default.
  final bool motionBlur;

  @override
  State<IconicMorph> createState() => _IconicMorphState();
}

class _IconicMorphState extends State<IconicMorph>
    with SingleTickerProviderStateMixin {
  // Built eagerly in initState, not lazily. A scrub-only morph never touches _ac
  // during its life, so a `late` init would defer construction to dispose() —
  // building a Ticker during unmounting throws "looking up a deactivated widget's
  // ancestor". Creating it here ensures dispose only ever disposes an existing one.
  late final AnimationController _ac;
  IconGeometry? _from;
  IconGeometry? _to;
  bool _kicked = false;

  // Prebuilt morph geometry — computed once per (icon, plan) change, not per
  // frame. Null until both geometries resolve; build shows a static [IconImage]
  // fallback until it is ready.
  MorphGeometry? _geom;

  // Cached reduce-motion value, read in didChangeDependencies. Async callbacks
  // and listeners must NOT call IconMotion.reduced(context) directly: an element can
  // be deactivated while still mounted, and an inherited widget lookup on a
  // deactivated element throws.
  bool _reduceMotion = false;

  /// Plan duration stretched by [IconicMorph.timeScale] (slow motion).
  Duration get _scaledDuration => Duration(
        microseconds:
            (widget.plan.duration.inMicroseconds * widget.timeScale).round(),
      );

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: _scaledDuration);
    _from = IconGeometry.peek(widget.from);
    _to = IconGeometry.peek(widget.to);
    if (_from == null || _to == null) _load();
    widget.controller?.addListener(_onController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (reduced-motion) is valid here — read + cache it so async/
    // listener callbacks never do an ancestor lookup on a deactivated element.
    _reduceMotion = IconMotion.reduced(context);
    // Geometry peeked in initState may already be ready — build it once here
    // (plan/icon changes after this go through didUpdateWidget/_load).
    if (_geom == null) _rebuildGeometry();
    _applyInitial();
  }

  // Rebuilds the [MorphGeometry] from the current geometries and plan. Only
  // called when (from, to, plan) actually change so scrubbing and playback
  // never trigger a recompute.
  void _rebuildGeometry() {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    _geom = MorphGeometry.build(from, to, widget.plan);
  }

  @override
  void didUpdateWidget(IconicMorph old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
    if (old.plan.duration != widget.plan.duration ||
        old.timeScale != widget.timeScale) {
      _ac.duration = _scaledDuration;
    }
    final iconsChanged = old.from != widget.from || old.to != widget.to;
    if (iconsChanged) {
      _from = IconGeometry.peek(widget.from);
      _to = IconGeometry.peek(widget.to);
      _kicked = false;
      if (_from == null || _to == null) {
        _load(); // async: rebuilds geometry on completion
        return;
      }
      _applyInitial();
    }
    // Recompute geometry only when icons or the plan value actually changed.
    // IconMorphPlan has value equality, so a copyWith that produces an identical
    // plan compares == and skips the recompute.
    if (iconsChanged || old.plan != widget.plan) _rebuildGeometry();
  }

  Future<void> _load() async {
    // Snapshot the pair across the await: if from/to swap mid-load, a stale
    // completion must NOT overwrite the newer pair's geometry (the later _load
    // for the current pair owns it). Without this the worm can flash the wrong
    // A→B if the old load resolves last.
    final from = widget.from, to = widget.to;
    final loaded = await Future.wait(
      [IconGeometry.load(from), IconGeometry.load(to)],
    );
    if (!mounted || from != widget.from || to != widget.to) return;
    setState(() {
      _from = loaded[0];
      _to = loaded[1];
      _rebuildGeometry();
    });
    _applyInitial();
  }

  /// First settle once both geometries are ready: morph or rest, honoring motion.
  void _applyInitial() {
    if (_from == null || _to == null || _kicked) return;
    _kicked = true;
    if (widget.scrub != null) return; // a timeline drives the frame — never play
    if (_reduceMotion) {
      // Settle on the visual target: forward → 1 (the [to] frame), reverse → 0
      // (the [from] frame, which a reversed morph ends on).
      _ac.value = widget.reverse ? 0 : 1;
    } else if (widget.autoplay) {
      _play();
    } else {
      _ac.value = widget.reverse ? 1 : 0; // rest on the source frame
    }
  }

  /// Run the morph in its configured direction: forward 0→1, or [reverse] 1→0
  /// (the same geometry/plan, every frame mirrored to `1 - t`).
  void _play() => widget.reverse ? _ac.reverse(from: 1) : _ac.forward(from: 0);

  void _onController() {
    if (!mounted) return;
    final c = widget.controller!;
    if (_from == null || _to == null) return; // geometry not ready yet
    if (c.stopRequested) {
      _ac.stop();
      _ac.value = widget.reverse ? 1 : 0; // back to the source frame
      return;
    }
    if (_reduceMotion) {
      _ac.value = widget.reverse ? 0 : 1;
      return;
    }
    _play();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    final geom = _geom;

    final Widget child = geom == null
        // Cold fallback = the VISUAL start frame: forward rests on [from], a
        // reverse rests on [to] (it plays to→from), so neither flashes the wrong
        // glyph before geometry resolves.
        ? IconImage.asset(widget.reverse ? widget.to : widget.from,
            size: widget.size, color: color)
        : RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: IconicMorphPainter(
                geom: geom,
                plan: widget.plan,
                color: color,
                reverse: widget.reverse,
                debugTangents: widget.debugTangents,
                motionBlur: widget.motionBlur,
                progress: widget.scrub != null
                    ? AlwaysStoppedAnimation<double>(widget.scrub!)
                    : _ac,
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

/// The painter behind [IconicMorph]. Holds only the prebuilt [MorphGeometry]
/// (no recompute here) + the animation knobs, and repaints off the controller via
/// `super(repaint:)`. Each frame is one cheap arc-length window walk.
class IconicMorphPainter extends CustomPainter {
  IconicMorphPainter({
    required this.geom,
    required this.plan,
    required this.color,
    required this.progress,
    this.reverse = false,
    this.debugTangents = false,
    this.strokeWidth = kIconStrokeWidth,
    this.motionBlur = false,
  }) : super(repaint: progress);

  /// Prebuilt morph geometry. Recomputed only when (from, to, plan) change;
  /// playback and scrubbing do no geometry work at all.
  final MorphGeometry geom;

  /// Animation knobs only (timing, fade, flip, perspective) — not geometry.
  final IconMorphPlan plan;
  final Color color;
  final Animation<double> progress;

  /// Whether this morph is playing as a reverse ("go back") transition — the
  /// controller runs 1→0 (see [IconicMorph.reverse]). Mirrors the worm's
  /// temporal easing AND lead role so it still launches fast / settles slow
  /// backward and peels off toward the source. See [_wormEnds].
  final bool reverse;

  /// Draw the head/tail direction probes (see [IconicMorph.debugTangents]).
  final bool debugTangents;

  /// Stroke width in viewBox units (the design token is 2 at a 24 viewBox).
  final double strokeWidth;

  /// Velocity-scaled motion blur on the worm (see [IconicMorph.motionBlur]).
  final bool motionBlur;

  /// Peak blur sigma (viewBox units) at mid-flight when [motionBlur] is on.
  static const double _blurMax = 0.9;

  // Fast-launch ease-out for the worm: peak velocity at the first frame,
  // decelerating into a long, soft settle. Direction-aware — a reverse play
  // mirrors this so the worm still launches fast and arrives slow going backward,
  // not a curve flip to slow-start/fast-end.
  static const Curve _ease = Cubic(0.25, 1.0, 0.5, 1.0);

  /// The worm's tail/head arc-length window at controller value [t], direction-
  /// aware in BOTH velocity and lead role. Forward (controller 0→1): the head
  /// leads up the target half (lSrc→lTot, outrunning the tail by [headLead])
  /// while the tail draws across from the source (0→sEntry) — the "draw-on".
  ///
  /// Reverse ("go back", controller 1→0): gesture progress is reframed as
  /// `1 - t` so [_ease] still gives fast-leave / slow-arrive in REAL time. The
  /// SMILE HEAD (right, lTot) leads — it flies the arc back and lands on the
  /// user's RIGHT (lSrc), the same point that launched it forward, outrunning by
  /// [headLead]; the smile's left entry trails to the user's left (sEntry→0).
  /// Head→head, right→right: the forward draw-on played back, no pinned smile.
  ({double tailS, double headS}) _wormEnds(double t) {
    final gp = reverse ? 1 - t : t; // gesture progress, 0→1 in real time
    final eHead = _ease.transform((gp * plan.headLead).clamp(0.0, 1.0));
    final eTail = _ease.transform(gp);
    if (!reverse) {
      return (
        tailS: geom.sEntry * eTail,
        headS: geom.lSrc + (geom.lTot - geom.lSrc) * eHead,
      );
    }
    return (
      // The SMILE HEAD (right, lTot) leads: it peels off and flies the arc back to
      // land on the user's RIGHT (lSrc) — the exact point that launched it going
      // forward — outrunning by [headLead]. The smile's left entry trails down to
      // the user's left (sEntry→0), drawing the user line on behind the landed
      // head. Head→head, right→right: a clean mirror of the forward draw-on, no
      // pinned smile.
      headS: geom.lTot - (geom.lTot - geom.lSrc) * eHead, // lTot → lSrc (lands user-right)
      tailS: geom.sEntry * (1 - eTail), //                   sEntry → 0  (trails to user-left)
    );
  }

  /// Exit window (fraction of the timeline) for [MorphExit.trim]: the leaving
  /// (non-hero) pieces UN-DRAW over this span. A featured pen-lift, so it's
  /// roomier than the fade/scale window — still capped under a smaller user
  /// `headFade`, and it clears well before the target assembles (`flipStart`).
  static const double _kTrimExitWindow = 0.35;

  /// Exit window for [MorphExit.fade] / [MorphExit.scale] — a snappy hide so the
  /// arriving glyph isn't competing with the old one.
  static const double _kFadeExitWindow = 0.18;

  /// Fraction of the exit window spent STAGGERING the per-contour start times
  /// (the remainder is the motion itself), so a many-part source (sun rays,
  /// hamburger bars) peels off in a cascade rather than all at once.
  static const double _kExitStaggerSpan = 0.45;

  /// Floor scale the assemble pieces grow FROM / shrink TO under
  /// [MorphAssemble.scale] (so they pop in/out, never to a literal zero).
  static const double _kAssembleScaleFloor = 0.35;

  /// Base stroke paint, built once and reused for every repaint (the painter is
  /// driven by `super(repaint:)`, so `paint()` runs once per frame on the SAME
  /// instance). Saves one Paint allocation per frame across the morph's life.
  Paint? _paint;
  Paint get _basePaint => _paint ??= (Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = color);

  @override
  void paint(Canvas canvas, Size size) {
    final vb = geom.viewBox;
    final s = size.shortestSide / vb;
    final paint = _basePaint;

    final t = progress.value.clamp(0.0, 1.0);
    final vbSize = Size(vb, vb);

    canvas.save();
    canvas.scale(s);
    _paintSourceRest(canvas, t, paint);
    _paintHero(canvas, t, paint);
    _paintFlips(canvas, vbSize, t, paint);
    canvas.restore();

    // Debug probes drawn AFTER restore, in device pixels, so "20px" is literal.
    if (debugTangents) _paintDebug(canvas, s, t);
  }

  /// Head/tail direction probes (debug). Recomputes the head + tail arc-lengths
  /// exactly as [_paintHero], then draws — in device pixels — a red line 12px
  /// AHEAD of the head along its forward tangent and an amber line 12px BEFORE
  /// the tail (backward). Marker dots sit on the actual head/tail points.
  void _paintDebug(Canvas canvas, double s, double t) {
    const probe = 20.0; // device pixels, for the tangent probe lines
    final ends = _wormEnds(t);
    final head = _sampleMaster(ends.headS);
    final tail = _sampleMaster(ends.tailS);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    const red = Color(0xFFFF3B30); // head: where it's heading
    const blue = Color(0xFF0A84FF); // tail: where it trails from

    // Head: 20px ahead along the forward tangent. Tangent is a unit vector
    // (scale-invariant), so * probe is already device pixels; the anchor is a
    // viewBox point, scaled to device by * s.
    final hp = head.pos * s;
    canvas.drawLine(hp, hp + head.tan * probe, line..color = red);
    canvas.drawCircle(hp, 3, Paint()..color = red);

    // Tail: 20px before (backward along the path).
    final tp = tail.pos * s;
    canvas.drawLine(tp, tp - tail.tan * probe, line..color = blue);
    canvas.drawCircle(tp, 3, Paint()..color = blue);
  }

  /// Position + unit forward tangent at global arc-length [s] along [master].
  ({Offset pos, Offset tan}) _sampleMaster(double s) {
    final cum = geom.cum, master = geom.master;
    final ss = s.clamp(0.0, geom.lTot);
    var seg = 1;
    while (seg < cum.length - 1 && cum[seg] < ss) {
      seg++;
    }
    final a = cum[seg - 1], b = cum[seg];
    final f = b > a ? ((ss - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
    return (
      pos: Offset.lerp(master[seg - 1], master[seg], f)!,
      tan: MorphGeometry.unit(master[seg] - master[seg - 1]),
    );
  }

  /// The travelling worm: a fixed set of points sampled between a moving tail and
  /// head along [master] (source → flight → target). The head leads, flies the
  /// curved arc, and lands on the target; the tail follows and draws it on.
  ///  • t = 0  → window = the source shape (the worm rests as the shoulders).
  ///  • mid    → window straddles the flight arc (the worm travels, curved).
  ///  • t = 1  → window = the target shape (the worm lies as the smile).
  void _paintHero(Canvas canvas, double t, Paint paint) {
    // Head outruns the tail (headLead) so the worm stretches over the flight and
    // settles as the tail lands — head reaches the target before the tail does.
    // Direction-aware (forward draws onto the target, reverse peels back toward
    // the source) — see [_wormEnds].
    final ends = _wormEnds(t);
    final tailS = ends.tailS, headS = ends.headS;

    var p = paint;
    if (motionBlur) {
      // Sigma peaks mid-flight (4·t·(1-t) = 0 at the ends, 1 at t=0.5) — blur
      // while travelling fast, dead-sharp at rest. One MaskFilter, ~free.
      final sigma = _blurMax * 4 * t * (1 - t);
      if (sigma > 0.02) {
        p = Paint()
          ..style = paint.style
          ..strokeWidth = paint.strokeWidth
          ..strokeCap = paint.strokeCap
          ..strokeJoin = paint.strokeJoin
          ..isAntiAlias = true
          ..color = paint.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
      }
    }
    canvas.drawPath(_worm(tailS, headS, geom.samples), p);
  }

  /// Sample [n] points evenly by arc length between [tailS] and [headS] along
  /// the master polyline. One forward walk of the cumulative table (both ends
  /// increase). The ONLY per-frame geometry work — everything else is prebuilt.
  Path _worm(double tailS, double headS, int n) {
    final cum = geom.cum, master = geom.master;
    final path = Path();
    var seg = 1;
    for (var j = 0; j < n; j++) {
      final s = tailS + (headS - tailS) * (n == 1 ? 0.0 : j / (n - 1));
      while (seg < cum.length - 1 && cum[seg] < s) {
        seg++;
      }
      final a = cum[seg - 1], b = cum[seg];
      final f = b > a ? ((s - a) / (b - a)).clamp(0.0, 1.0) : 0.0;
      final p = Offset.lerp(master[seg - 1], master[seg], f)!;
      if (j == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  /// The source's non-hero contours (e.g. the user's head ring) LEAVE as the
  /// morph runs, choreographed by [IconMorphPlan.exit] — decoupled from how the
  /// target ARRIVES ([plan.assemble]):
  ///  • [MorphExit.trim] (default): each **un-draws** — retracts along its own
  ///    length from its open end (the temporal mirror of the target's draw-on),
  ///    at full alpha. A real pen-lift, NOT a fade.
  ///  • [MorphExit.fade]: alpha fades to 0 (the original behavior).
  ///  • [MorphExit.scale]: shrinks toward the glyph center while fading.
  ///
  /// Multiple leaving contours **cascade** — each starts a touch later — so a
  /// many-part source (sun rays, hamburger bars) peels off in sequence. Every
  /// piece is a pure function of [t], so a reverse ("go back") play rewinds it
  /// exactly: the source re-draws itself back on.
  void _paintSourceRest(Canvas canvas, double t, Paint paint) {
    final rest = geom.srcRest;
    final n = rest.length;
    if (n == 0) return;
    final exit = plan.exit;
    // Un-draw is a featured motion → give it room to read; fade/scale hide fast.
    // A smaller user-set headFade still caps either.
    final window = math.min(
      plan.headFade,
      exit == MorphExit.trim ? _kTrimExitWindow : _kFadeExitWindow,
    );
    // Spread the per-contour start times across a fraction of the window (the
    // remainder is the motion), so even the last contour finishes inside it.
    final maxStart = window * _kExitStaggerSpan;
    final step = n <= 1 ? 0.0 : maxStart / (n - 1);
    for (var i = 0; i < n; i++) {
      final winStart = step * i;
      final prog = _smoothstep(winStart, window, t); // 0 (present) → 1 (gone)
      _paintLeavingContour(canvas, rest[i], exit, prog, paint);
    }
  }

  /// Paint ONE leaving contour at exit-progress [prog] (0 = fully present, 1 =
  /// fully gone) under the chosen [exit] choreography. See [_paintSourceRest].
  void _paintLeavingContour(
    Canvas canvas,
    IconContour c,
    MorphExit exit,
    double prog,
    Paint paint,
  ) {
    if (prog >= 1) return; // fully gone — nothing to paint
    if (prog <= 0) {
      canvas.drawPath(c.polygon, paint); // fully present — cached path, no rebuild
      return;
    }
    switch (exit) {
      case MorphExit.trim:
        // ── Length: retract from the open end, full → 0 as prog 0 → 1. ONE
        // shaping curve on top of the smoothstep'd window. (It used to be an
        // easeOutCubic ON TOP of that smoothstep — a double ease that spent 99%
        // of the length in the first 70% of the exit and then left a stub parked
        // on screen for the rest, which is what read as a dot.) easeOutQuad keeps
        // the exit decisive — three quarters of the ink gone by the midpoint, so
        // it still clears well before the target assembles — without parking.
        final e = Curves.easeOutQuad.transform(prog);
        final visible = 1 - e;
        // ── Weight: the ink also RUNS OUT. Past plan.exitTaper the stroke thins
        // to nothing, and the no-dot clamp independently forbids ink wider than a
        // third of the length it has left — so the retract ends as a vanishing
        // hair, never as the round-cap dot a length-only trim always ends on.
        final w = math.min(
          StrokeTaper.out(prog, plan.exitTaper),
          StrokeTaper.lengthClamp(c.length * visible, c.length, strokeWidth),
        );
        final p = StrokeTaper.weighted(paint, w);
        if (p == null) return; // ink spent — draw nothing (width 0 = hairline!)
        canvas.drawPath(PathMorph.trimmedRange(c, 0, visible), p);
      case MorphExit.fade:
        canvas.drawPath(c.polygon, tintStroke(paint, 1 - prog));
      case MorphExit.scale:
        // Shrink toward the glyph center while fading.
        final cc = geom.viewBox / 2;
        final sc = 1 - (1 - _kAssembleScaleFloor) * prog; // 1 → floor
        canvas.save();
        canvas.translate(cc, cc);
        canvas.scale(sc);
        canvas.translate(-cc, -cc);
        canvas.drawPath(c.polygon, tintStroke(paint, 1 - prog));
        canvas.restore();
    }
  }

  /// The rest of the target assembles around the travelling line, staggered (delay
  /// normalized so even a dense glyph lands by t = 1).
  ///  • [MorphAssemble.trim] (default): each piece is **drawn on (trim-path)** from
  ///    0 → full length as the hero line lands — the whole glyph finishes as one
  ///    harmonious stroke, no fade.
  ///  • [MorphAssemble.scale]: each piece **scales IN** from small → full about the
  ///    glyph center, fading in.
  ///  • [MorphAssemble.flip3d]: the original constant-stroke 3D flip-in.
  void _paintFlips(Canvas canvas, Size size, double t, Paint paint) {
    final flips = geom.flips;
    final n = flips.length;
    if (n == 0) return;
    final center = size.width / 2;
    final maxSpread = (1 - plan.flipStart) * 0.5;
    final step = n <= 1 ? 0.0 : plan.flipStagger.clamp(0.0, maxSpread / (n - 1));
    final proj = plan.assemble == MorphAssemble.flip3d
        ? Projector3D(perspective: plan.perspective)
        : null;

    for (var i = 0; i < n; i++) {
      final winStart = plan.flipStart + step * i;
      final span = 1 - winStart;
      final local = span <= 0 ? 1.0 : ((t - winStart) / span).clamp(0.0, 1.0);
      if (local <= 0) continue; // not arrived yet
      final e = Curves.easeOutCubic.transform(local);

      switch (plan.assemble) {
        case MorphAssemble.trim:
          // Draw-on: reveal the contour along its own length as the line lands —
          // and let the nib PRESS DOWN as it starts (plan.assembleTaper) instead
          // of stamping a full-weight round-cap dot on the first frame. Same
          // no-dot clamp as the exit, so the entry can never blob whatever the
          // knob says. This is the exit's mirror: weight in, weight out.
          final c = flips[i];
          final w = math.min(
            StrokeTaper.into(local, plan.assembleTaper),
            StrokeTaper.lengthClamp(c.length * e, c.length, strokeWidth),
          );
          final p = StrokeTaper.weighted(paint, w);
          if (p != null) canvas.drawPath(PathMorph.trimmedContour(c, e), p);
        case MorphAssemble.flip3d:
          final angle = Projector3D.kEdgeOnEntryAngle * (1 - e); // edge-on → flat
          final sub = proj!.projectPolyline(
            flips[i].points,
            angle,
            center,
            closed: flips[i].isClosed,
          );
          canvas.drawPath(sub, tintStroke(paint, Curves.easeOut.transform(local)));
        case MorphAssemble.scale:
          // grow floor → 1 about the glyph center
          final sc = _kAssembleScaleFloor + (1 - _kAssembleScaleFloor) * e;
          canvas.save();
          canvas.translate(center, center);
          canvas.scale(sc);
          canvas.translate(-center, -center);
          canvas.drawPath(
            flips[i].polygon, // cached; never rebuilt per frame
            tintStroke(paint, Curves.easeOut.transform(local)),
          );
          canvas.restore();
      }
    }
  }

  /// Hermite smoothstep over [a..b] — a soft 0→1 ramp for the source's dissolve.
  /// Remaps into [0,1] then defers to the single shared [MorphGeometry.smooth01]
  /// (the same cubic the flight bow uses) — no second copy of the math.
  double _smoothstep(double a, double b, double x) {
    if (b <= a) return x < a ? 0.0 : 1.0;
    return MorphGeometry.smooth01((x - a) / (b - a));
  }

  @override
  bool shouldRepaint(IconicMorphPainter old) =>
      !identical(old.geom, geom) ||
      old.plan != plan ||
      old.color != color ||
      old.reverse != reverse ||
      old.strokeWidth != strokeWidth ||
      old.debugTangents != debugTangents ||
      old.motionBlur != motionBlur ||
      old.progress.value != progress.value; // scrub: AlwaysStopped won't notify
}
