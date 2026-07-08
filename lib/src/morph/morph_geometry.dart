import 'package:flutter/widgets.dart';

import '../icon_geometry.dart';
import 'morph_plan.dart';
import 'path_morph.dart';

/// All morph geometry that depends only on (from, to, plan) — the precomputed
/// hero lines, quintic flight curve, master polyline + arc-length table, and the
/// source/target contour lists. Built once per (icon, plan) change and handed to
/// the painter so per-frame repaints do zero geometry work.
///
/// Also houses the reusable [flightCurve] primitive and [resolveHeroLines] —
/// pure functions with no painting or widget dependencies, available for external
/// use (e.g. a custom debug overlay).
@immutable
class MorphGeometry {
  const MorphGeometry({
    required this.master,
    required this.cum,
    required this.lSrc,
    required this.sEntry,
    required this.lTot,
    required this.srcRest,
    required this.flips,
    required this.viewBox,
    required this.samples,
  });

  final List<Offset> master; // source → flight → target, one polyline
  final List<double> cum; // cumulative arc length along [master]
  final double lSrc; // arc length where the source shape ends
  final double sEntry; // arc length where the target shape begins
  final double lTot; // total arc length
  final List<IconContour> srcRest; // source's other contours → leave (per plan.exit)
  final List<IconContour> flips; // target's other contours → arrive (per plan.assemble)
  final double viewBox;
  final int samples; // worm render-point count (= plan.samples at build time)

  static MorphGeometry build(
    IconGeometry from,
    IconGeometry to,
    IconMorphPlan plan,
  ) {
    // resolveSource/resolveHeroTarget return 0 for an empty contour list, which
    // the indexing below would then read past — fail loud on an icon that parsed
    // to zero contours (empty/typo'd SVG or manifest 'd').
    assert(
      from.contours.isNotEmpty && to.contours.isNotEmpty,
      'IconicMorph: "from"/"to" icon parsed to zero contours — check the '
      'SVG/manifest path data.',
    );
    final n = plan.samples;
    final heroIdx = plan.resolveHeroTarget(to.contours);
    final srcIdx = plan.resolveSource(from.contours);
    // Hero lines resolved via resolveHeroLines (so any debug overlay reads the
    // same geometry), oriented for travel.
    final hero = resolveHeroLines(from, to, plan);
    final src = hero.src, dst = hero.dst;
    // The travel arc: the quintic-Hermite flight (launch/landing breathing + bow)
    // from the source head, along its tangent, to the target entry along its
    // tangent. [flightCurve] includes both endpoints; drop them (the master path
    // already supplies the head via src and the entry via dst).
    // Walk inward past any coincident end samples so a degenerate resample at the
    // head/entry doesn't collapse the launch/landing tangent to unit()'s
    // straight-up (0,-1) fallback — which would launch the worm the wrong way.
    final headTan = _endTangent(src, fromEnd: true);
    final entryTan = _endTangent(dst, fromEnd: false);
    final full = flightCurve(
      src.last,
      headTan,
      dst.first,
      entryTan,
      launch: plan.flightLaunch,
      land: plan.flightLand,
      bow: plan.flightBow,
      bias: plan.flightBias,
      runway: plan.flightRunway,
    );
    final flight = full.sublist(1, full.length - 1);

    final master = <Offset>[...src, ...flight, ...dst];
    final cum = List<double>.filled(master.length, 0);
    for (var i = 1; i < master.length; i++) {
      cum[i] = cum[i - 1] + (master[i] - master[i - 1]).distance;
    }
    return MorphGeometry(
      master: master,
      cum: cum,
      lSrc: cum[n - 1], // end of the source shape
      sEntry: cum[n + flight.length], // start of the target shape
      lTot: cum.last,
      srcRest: [
        for (var i = 0; i < from.contours.length; i++)
          if (i != srcIdx) from.contours[i],
      ],
      flips: [
        for (var i = 0; i < to.contours.length; i++)
          if (i != heroIdx) to.contours[i],
      ],
      viewBox: to.viewBox,
      samples: n,
    );
  }

  /// Resolve + orient the two hero lines exactly as the morph travels them: the
  /// SOURCE line with its head (the launch end) on the RIGHT, and the TARGET
  /// line oriented LEFT→RIGHT (entry = left/tail, head = right). Shared by the
  /// painter and the flight-design debug overlay so the two never drift.
  ///
  /// Orientation note: the default head/tail choice is by x-coordinate (left-to-
  /// right bias). For a near-vertical hero line this discriminator is weak and the
  /// chosen end is effectively arbitrary; for an RTL-natural glyph the default may
  /// read "backwards". Use [IconMorphPlan.flipSource] / [flipTarget] to swap the
  /// ends explicitly rather than relying on this heuristic.
  static ({List<Offset> src, List<Offset> dst}) resolveHeroLines(
    IconGeometry from,
    IconGeometry to,
    IconMorphPlan plan,
  ) {
    assert(
      from.contours.isNotEmpty && to.contours.isNotEmpty,
      'IconicMorph: "from"/"to" icon parsed to zero contours — check the '
      'SVG/manifest path data.',
    );
    final n = plan.samples;
    var src = PathMorph.resampleContour(
      from.contours[plan.resolveSource(from.contours)],
      n,
    );
    if (src.first.dx > src.last.dx) src = src.reversed.toList();
    if (plan.flipSource) src = src.reversed.toList(); // swap source head/tail
    final heroDst = PathMorph.resampleContour(
      to.contours[plan.resolveHeroTarget(to.contours)],
      n,
    );
    var dst = heroDst.first.dx <= heroDst.last.dx
        ? heroDst
        : heroDst.reversed.toList();
    if (plan.flipTarget) dst = dst.reversed.toList(); // swap target entry/head
    return (src: src, dst: dst);
  }

  /// A **natural, flowing** flight between two oriented ends. Base shape = a
  /// **quintic Hermite with zero curvature at both ends**: it LEAVES [from] along
  /// [fromTan] *flat* (curvature 0 → a smooth runway, not a tight hook), eases its
  /// bend in over the middle, and ARRIVES at [to] along [toTan] *flat* again —
  /// real launch/landing breathing, no sharp end-turn. [launch] / [land] are the
  /// two end-velocity magnitudes (fraction of the gap) — how gradual the take-off
  /// and touchdown are, split so each breathes independently.
  ///
  /// On its own a flat-ended quintic packs ALL its turning into the middle, so
  /// when [fromTan] and [toTan] near-oppose it reverses hard there (the recurring
  /// "sharp turn"). [bow] cures that: a signed lateral hump (fraction of the gap)
  /// perpendicular to the chord that swings the whole path wide to ONE side,
  /// spreading the reversal into a single broad arc. The hump is flat at both
  /// ends, so it never disturbs the launch/landing tangents; [bias] slides where
  /// it peaks. Sign of [bow] picks the side (CW vs CCW). [runway] prepends/appends
  /// a STRAIGHT segment along each tangent (the literal "Npx ahead/before"), so
  /// the curve only starts bending after that breathing gap. Both endpoints included.
  static List<Offset> flightCurve(
    Offset from,
    Offset fromTan,
    Offset to,
    Offset toTan, {
    double launch = 0.5,
    double land = 0.5,
    double bow = 0.0,
    double bias = 0.5,
    double runway = 0.0,
    int steps = 64,
  }) {
    final fu = unit(fromTan), tu = unit(toTan);
    final fullGap = (to - from).distance;
    if (fullGap < 1e-6) return [from, to];

    // [runway]: a STRAIGHT breathing segment along the tangent at each end before
    // the curve is allowed to bend — the literal "Npx ahead of the head / before
    // the tail." The quintic then runs between the runway ends (p1..q1), so launch
    // and landing leave/arrive dead straight for `runway` units, then curve.
    final r = runway.clamp(0.0, fullGap * 0.45);
    final p1 = from + fu * r; // launch runway end (curve starts here)
    final q1 = to - tu * r; // landing runway start (curve ends here)

    final chord = q1 - p1;
    final gap = chord.distance;
    if (gap < 1e-6) return [from, p1, q1, to];
    final v0 = fu * (launch.clamp(0.05, 2.0) * gap);
    final v1 = tu * (land.clamp(0.05, 2.0) * gap);

    // Lateral hump (the bow): perpendicular to the (inner) chord, signed by [bow].
    // It is 0 AND flat at both ends, so it adds no end-velocity — the launch/
    // landing tangents stay exactly the Hermite's. Peaks at [bias].
    final dir = chord / gap;
    final perp = Offset(-dir.dy, dir.dx); // chord rotated +90°
    final amp = bow * gap;
    final b = bias.clamp(0.05, 0.95);

    final out = <Offset>[from]; // straight launch runway: from → p1
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final u2 = u * u, u3 = u2 * u, u4 = u3 * u, u5 = u4 * u;
      // Quintic Hermite with acceleration = 0 at both ends (those terms drop out).
      final h0 = 1 - 10 * u3 + 15 * u4 - 6 * u5; // p1
      final h1 = u - 6 * u3 + 8 * u4 - 3 * u5; // v0 (launch velocity)
      final h4 = -4 * u3 + 7 * u4 - 3 * u5; // v1 (landing velocity)
      final h5 = 10 * u3 - 15 * u4 + 6 * u5; // q1
      var p = p1 * h0 + v0 * h1 + v1 * h4 + q1 * h5;
      if (amp != 0) {
        // Smoothstep bump: 0 + zero-slope at u=0 and u=1, =1 at u=bias. Zero slope
        // at the ends is what keeps the launch/landing tangents untouched.
        final w = u <= b ? smooth01(u / b) : smooth01((1 - u) / (1 - b));
        p += perp * (amp * w);
      }
      out.add(p);
    }
    out.add(to); // straight landing runway: q1 → to
    return out;
  }

  /// Unit vector of [v] (falls back to straight up for a zero vector). Public so
  /// the painter (a separate file) can use it for tangents without re-deriving.
  static Offset unit(Offset v) {
    final d = v.distance;
    return d < 1e-6 ? const Offset(0, -1) : v / d;
  }

  /// Unit tangent at an end of [pts]: from the second-to-last toward the last
  /// ([fromEnd] true) or the first toward the second (false), walking PAST any
  /// coincident samples so a degenerate resample at the end yields the contour's
  /// real direction instead of [unit]'s straight-up fallback.
  static Offset _endTangent(List<Offset> pts, {required bool fromEnd}) {
    if (pts.length < 2) return const Offset(0, -1);
    if (fromEnd) {
      final tip = pts.last;
      for (var i = pts.length - 2; i >= 0; i--) {
        final v = tip - pts[i];
        if (v.distance >= 1e-6) return v / v.distance;
      }
    } else {
      final tip = pts.first;
      for (var i = 1; i < pts.length; i++) {
        final v = pts[i] - tip;
        if (v.distance >= 1e-6) return v / v.distance;
      }
    }
    return const Offset(0, -1);
  }

  /// Hermite smoothstep 0→1 over [0,1] with zero slope at both ends — for
  /// [flightCurve]'s bow hump, and the single shared smoothstep the morph
  /// painter's `_smoothstep` also delegates to (no duplicated cubic).
  static double smooth01(double x) {
    final u = x.clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }
}
