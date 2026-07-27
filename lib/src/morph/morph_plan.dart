import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import 'path_morph.dart';

/// How a morph's ARRIVING (target non-hero) contours assemble around the
/// travelling hero line — the bits of the NEW glyph that aren't the line that
/// flies. Decoupled from how the OLD glyph leaves ([MorphExit]).
enum MorphAssemble {
  /// Arriving pieces **draw on via trim-path** (pen-drawn from 0 → full length) as
  /// the hero line lands, so the whole glyph completes as one harmonious stroke.
  /// Default.
  trim,

  /// Arriving pieces **scale in** from small → full about the glyph center — a
  /// zoom/pop, not a dissolve.
  scale,

  /// Arriving pieces **flip in** via the constant-stroke 3D projector. The
  /// original choreography (kept for when depth is wanted).
  flip3d,
}

/// How a morph's LEAVING (source non-hero) contours disappear — the bits of the
/// OLD glyph that aren't the source hero line. Decoupled from [MorphAssemble]
/// (how the new glyph arrives) so entrance and exit choreograph independently.
enum MorphExit {
  /// Leaving pieces **un-draw**: each retracts along its own length from its open
  /// end (trim-path reversed), the pen lifting and pulling the ink back — the
  /// temporal mirror of the target's [MorphAssemble.trim] draw-on. Not the
  /// [fade] dissolve, which is gone from frame one: the ink retracts at its true
  /// weight and only dissolves over the last of the exit
  /// ([IconMorphPlan.exitFade]) — so the stroke lifts away instead of ending on
  /// a round-cap dot. This is the default.
  trim,

  /// Leaving pieces **fade** their alpha to 0 — the original behavior, kept as an
  /// escape hatch for pairs where an un-draw reads busy.
  fade,

  /// Leaving pieces **shrink** toward the glyph center while fading — a zoom-out.
  scale,
}

/// Recipe for a `IconicMorph` — how the source glyph becomes the target.
///
/// The choreography the user feels — a travelling "worm", not a cross-fade:
///  1. One real line of the SOURCE is the hero — e.g. the user's **shoulders
///     arc**, picked by [sourceAnchor]. The worm rests on it.
///  2. Its **head launches** along the line's own tangent and **flies a smooth
///     quintic-Hermite curve** ([flightLaunch], [flightLand], [flightBow],
///     [flightBias]) over to the entry of a real TARGET line — e.g. the face's
///     **smile**, picked by [heroAnchor] — arriving along the target's tangent so
///     it eases in, never cutting across.
///  3. The worm **slides onto the target**, the tail catching up ([headLead])
///     and drawing the smile on. Mechanically: a fixed-length window slides by
///     arc length along one master path (source → flight → target).
///  4. Meanwhile the source's other contours (the head ring) **leave** — by
///     default they **un-draw / retract** ([MorphExit.trim]) rather than fade —
///     and the target's others (brackets, eyes, nose) **draw on** ([MorphAssemble]
///     — trim / scale / 3D flip), assembling the new icon around the line that
///     travelled.
///
/// Everything is a tunable here so the SAME engine drives any pair of icons.
/// This is pure data — the geometry it produces lives in `MorphGeometry`, the
/// painting in `IconicMorphPainter`.
@immutable
class IconMorphPlan {
  const IconMorphPlan({
    this.duration = IconMotion.iconMorph,
    this.samples = 200,
    this.heroAnchor,
    this.heroTargetIndex,
    this.sourceAnchor = const Offset(12, 20),
    this.sourceIndex,
    this.flightLaunch = 1.5,
    this.flightLand = 1.5,
    this.flightBow = -0.40,
    this.flightBias = 0.5,
    this.flightRunway = 2.0,
    this.headLead = 2.2,
    this.headFade = 0.45,
    this.flipStart = 0.55,
    this.flipStagger = 0.1,
    this.exitTaper = 0.5,
    this.exitFade = 0.75,
    this.taperFloor = 1,
    this.assembleTaper = 0.18,
    this.perspective = 0.0028,
    this.assemble = MorphAssemble.trim,
    this.exit = MorphExit.trim,
    this.flipSource = false,
    this.flipTarget = false,
  })  : assert(headLead >= 1,
            'headLead must be >= 1 so the worm head never trails its tail '
            '(headS < tailS makes the arc-length window degenerate).'),
        assert(samples >= 2, 'samples must be >= 2 — a line needs two ends.');

  /// Total play time. Prefer [IconMotion] constants for consistent timing.
  final Duration duration;

  /// Points the hero source + target lines are each resampled to. More = a
  /// smoother morph at a little more cost. >= 2.
  final int samples;

  /// Viewbox-space point used to pick the hero TARGET contour: the contour whose
  /// centroid is nearest this anchor becomes the morph's destination line — e.g.
  /// `Offset(12, 16)` for a mouth. Order-independent, so it's the robust selector.
  final Offset? heroAnchor;

  /// Explicit hero target contour index — wins over [heroAnchor] when set.
  final int? heroTargetIndex;

  /// Viewbox-space point used to pick the hero SOURCE contour — the line that
  /// morphs into the target. Defaults to the glyph's lower edge `Offset(12, 20)`,
  /// e.g. the user's shoulders arc.
  final Offset? sourceAnchor;

  /// Explicit hero source contour index — wins over [sourceAnchor] when set.
  final int? sourceIndex;

  /// **Launch breathing** — the quintic launch-velocity as a fraction of the
  /// head→entry gap (≈0.15–0.9). Higher = the flight eases OUT more gradually off
  /// the source tangent (a longer, gentler take-off runway).
  final double flightLaunch;

  /// **Landing breathing** — the quintic landing-velocity as a fraction of the
  /// gap (≈0.15–0.9). Higher = it eases IN more gradually onto the target tangent
  /// (a longer, gentler touchdown). Split from [flightLaunch] so take-off and
  /// landing can breathe independently.
  final double flightLand;

  /// **Lateral bow** — signed swing perpendicular to the head→entry chord, as a
  /// fraction of the gap (≈ -0.8…0.8; 0 = no swing). When the two tangents
  /// near-oppose, a straight flight has to reverse hard through the middle (the
  /// "sharp turn"); a bow swings the whole path wide to ONE side instead, turning
  /// that reversal into a single broad arc. Sign picks the side (CW vs CCW); you
  /// own the magnitude so it never balloons. Added as a bump that's flat at both
  /// ends, so it never disturbs the launch/landing tangents.
  final double flightBow;

  /// **Bow position** — where along the flight the [flightBow] hump peaks (0..1;
  /// 0.5 = mid). Shift toward 0 to fatten the launch side, toward 1 the landing.
  final double flightBias;

  /// **Runway** — a STRAIGHT breathing segment (viewBox units, e.g. ~20 at a 24
  /// viewBox) along the tangent at EACH end before the curve is allowed to bend.
  /// The launch leaves dead-straight for this far, then curves; the landing
  /// arrives dead-straight for the last stretch. 0 = the curve bends immediately
  /// off the tangent (no straight runway). Clamped to ≤ 45% of the head→entry gap.
  final double flightRunway;

  /// How much the worm's head leads its tail in time (>1). 1 = head and tail
  /// move together (it slides rigidly); higher = the head launches ahead and the
  /// tail catches up, so the worm stretches out over the flight and draws the
  /// target on as the tail lands.
  final double headLead;

  /// Window [0..headFade] over which the source's non-hero contours LEAVE as the
  /// morph runs — it caps whichever [exit] choreography is active (un-draw, fade,
  /// or shrink), NOT just a fade. Default 0.45; the trim un-draw then caps at 0.35
  /// and fade/scale at 0.18, so a smaller headFade tightens the active exit.
  final double headFade;

  /// When the target's non-hero contours start flipping in (0..1).
  final double flipStart;

  /// Per-contour flip-in delay (auto-normalized to the contour count).
  final double flipStagger;

  /// **Pen-lift taper** (0..1) — the point in a leaving contour's exit after which
  /// its STROKE WEIGHT starts easing down toward [taperFloor].
  ///
  /// **Inert unless [taperFloor] is lowered below 1**, which it is not by default:
  /// weight modulation is per-contour, and a staggered exit therefore paints
  /// neighbouring contours at different weights, so the glyph stops reading as
  /// one balanced drawing. [exitFade] is the default vanish instead.
  final double exitTaper;

  /// **Dissolve span** (0..1) — a leaving contour's ALPHA fades to nothing over
  /// the last `1 - exitFade` of the **whole animation**. **This is the whole
  /// vanish.** Default 0.75 = a quarter of the morph, ≈160 ms at the default
  /// [duration].
  ///
  /// Two things make it read as a fade rather than a cut, and both are easy to
  /// get wrong:
  ///
  ///  * **It ends at the dot horizon**, not when the length runs out — the
  ///    moment this contour's shrinking ink would stop reading as a line and
  ///    start reading as a round-cap dot. Nothing is drawn past that. Fade to
  ///    the end of the exit instead and the dot is still on screen at 30–70%
  ///    alpha. The span is therefore honoured but slid earlier, per contour, by
  ///    that contour's own length.
  ///  * **It is measured in real time, not in exit progress.** Progress is
  ///    smoothstepped across the contour's window, so a quarter of *progress*
  ///    lands where the smoothstep is moving fastest — 43 ms, under three
  ///    frames. A quarter of the *timeline* is 160 ms.
  ///
  /// Alpha, not weight, is what can remove a stroke without unbalancing the
  /// glyph — see [taperFloor]. 1 = no fade (a hard cut when the length runs out).
  final double exitFade;

  /// **Ink floor** (0..1) — how thin a taper may ever take the stroke, at either
  /// end. **Default 1: stroke weight is never touched.**
  ///
  /// Lower it (e.g. 0.5) for a deliberate pen-lift, which enables [exitTaper],
  /// [assembleTaper] AND the engine's no-dot clamp together. There is no middle
  /// setting where weight is modulated only for degenerate geometry: either ink
  /// keeps its weight everywhere, or the taper owns it.
  final double taperFloor;

  /// **Nib press-down** (0..1) — the fraction of an arriving contour's draw-on
  /// ([MorphAssemble.trim]) over which its stroke weight ramps from [taperFloor]
  /// up to full, the mirror of [exitTaper]. Like it, **inert unless [taperFloor]
  /// is lowered below 1**. Default 0.18.
  final double assembleTaper;

  /// 3D perspective strength for the flip-in (used only when [assemble] is
  /// [MorphAssemble.flip3d]; see `Projector3D`).
  final double perspective;

  /// How the ARRIVING (target) non-hero contours assemble — [MorphAssemble.trim]
  /// (draw-on, the default), [MorphAssemble.scale] (zoom in), or
  /// [MorphAssemble.flip3d] (the 3D flip). Governs the NEW glyph only.
  final MorphAssemble assemble;

  /// How the LEAVING (source) non-hero contours disappear — [MorphExit.trim]
  /// (un-draw / retract, the default), [MorphExit.fade] (alpha fade), or
  /// [MorphExit.scale] (shrink + fade). Governs the OLD glyph only, independent
  /// of [assemble].
  final MorphExit exit;

  /// Reverse the resolved SOURCE hero line (swap its head/tail) AFTER the default
  /// "head on the right" orientation — so the worm launches from the other end of
  /// the source line. Use per-direction when the default end reads wrong.
  final bool flipSource;

  /// Reverse the resolved TARGET hero line (swap entry/head) AFTER the default
  /// "entry on the left" orientation — so the worm lands lying the other way.
  final bool flipTarget;

  /// Which target contour the source morphs INTO.
  int resolveHeroTarget(List<IconContour> targets) =>
      _pick(targets, heroAnchor, heroTargetIndex);

  /// Which source contour is the one that morphs (the rest fade out).
  int resolveSource(List<IconContour> sources) =>
      _pick(sources, sourceAnchor, sourceIndex);

  /// Returns a copy with selected fields overridden. Useful for tuning a base
  /// plan without mutating it — e.g. a slider can override [flightBow] while
  /// keeping all other fields from the original.
  IconMorphPlan copyWith({
    Duration? duration,
    int? samples,
    Offset? heroAnchor,
    int? heroTargetIndex,
    Offset? sourceAnchor,
    int? sourceIndex,
    double? flightLaunch,
    double? flightLand,
    double? flightBow,
    double? flightBias,
    double? flightRunway,
    double? headLead,
    double? headFade,
    double? flipStart,
    double? flipStagger,
    double? exitTaper,
    double? exitFade,
    double? taperFloor,
    double? assembleTaper,
    double? perspective,
    MorphAssemble? assemble,
    MorphExit? exit,
    bool? flipSource,
    bool? flipTarget,
  }) =>
      IconMorphPlan(
        duration: duration ?? this.duration,
        samples: samples ?? this.samples,
        heroAnchor: heroAnchor ?? this.heroAnchor,
        heroTargetIndex: heroTargetIndex ?? this.heroTargetIndex,
        sourceAnchor: sourceAnchor ?? this.sourceAnchor,
        sourceIndex: sourceIndex ?? this.sourceIndex,
        flightLaunch: flightLaunch ?? this.flightLaunch,
        flightLand: flightLand ?? this.flightLand,
        flightBow: flightBow ?? this.flightBow,
        flightBias: flightBias ?? this.flightBias,
        flightRunway: flightRunway ?? this.flightRunway,
        headLead: headLead ?? this.headLead,
        headFade: headFade ?? this.headFade,
        flipStart: flipStart ?? this.flipStart,
        flipStagger: flipStagger ?? this.flipStagger,
        exitTaper: exitTaper ?? this.exitTaper,
        exitFade: exitFade ?? this.exitFade,
        taperFloor: taperFloor ?? this.taperFloor,
        assembleTaper: assembleTaper ?? this.assembleTaper,
        perspective: perspective ?? this.perspective,
        assemble: assemble ?? this.assemble,
        exit: exit ?? this.exit,
        flipSource: flipSource ?? this.flipSource,
        flipTarget: flipTarget ?? this.flipTarget,
      );

  // Value equality so that a copyWith producing identical fields compares == the
  // original — allowing the morph to skip the geometry recompute when nothing
  // actually changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IconMorphPlan &&
          other.duration == duration &&
          other.samples == samples &&
          other.heroAnchor == heroAnchor &&
          other.heroTargetIndex == heroTargetIndex &&
          other.sourceAnchor == sourceAnchor &&
          other.sourceIndex == sourceIndex &&
          other.flightLaunch == flightLaunch &&
          other.flightLand == flightLand &&
          other.flightBow == flightBow &&
          other.flightBias == flightBias &&
          other.flightRunway == flightRunway &&
          other.headLead == headLead &&
          other.headFade == headFade &&
          other.flipStart == flipStart &&
          other.flipStagger == flipStagger &&
          other.exitTaper == exitTaper &&
          other.exitFade == exitFade &&
          other.taperFloor == taperFloor &&
          other.assembleTaper == assembleTaper &&
          other.perspective == perspective &&
          other.assemble == assemble &&
          other.exit == exit &&
          other.flipSource == flipSource &&
          other.flipTarget == flipTarget;

  // hashAll, not Object.hash: the field list is past that helper's 20-argument
  // ceiling, and a silently truncated hash would let two plans that differ only
  // in a late field collide.
  @override
  int get hashCode => Object.hashAll([
        duration,
        samples,
        heroAnchor,
        heroTargetIndex,
        sourceAnchor,
        sourceIndex,
        flightLaunch,
        flightLand,
        flightBow,
        flightBias,
        flightRunway,
        headLead,
        headFade,
        flipStart,
        flipStagger,
        exitTaper,
        exitFade,
        taperFloor,
        assembleTaper,
        perspective,
        assemble,
        exit,
        flipSource,
        flipTarget,
      ]);

  /// Pick a contour by explicit [index] (wins), else nearest-centroid to
  /// [anchor], else the longest OPEN contour (closed rings de-weighted so a
  /// frame doesn't win).
  static int _pick(List<IconContour> cs, Offset? anchor, int? index) {
    if (cs.isEmpty) return 0;
    if (index != null) return index.clamp(0, cs.length - 1);

    if (anchor != null) {
      var best = 0;
      var bestD = double.infinity;
      for (var i = 0; i < cs.length; i++) {
        final d = (PathMorph.centroid(cs[i].points) - anchor).distanceSquared;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      return best;
    }

    var best = 0;
    var bestLen = -1.0;
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final len = c.length * (c.isClosed ? 0.6 : 1.0);
      if (len > bestLen) {
        bestLen = len;
        best = i;
      }
    }
    return best;
  }
}
