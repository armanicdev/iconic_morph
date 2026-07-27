import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/src/icon_effect.dart';
import 'package:iconic_morph/src/morph/morph_plan.dart';
import 'package:iconic_morph/src/stroke_taper.dart';

/// Locks the weight law for trim-path ends — the fix for "the ink ends on a dot
/// and then blinks out". Two facts drive every assertion here:
///
///  * a round-capped stroke SHORTER than its own width renders as a dot, so ink
///    must lose weight as it loses length, and
///  * `Paint.strokeWidth = 0` is Skia's HAIRLINE mode (a 1px line), not
///    invisibility — so a spent stroke must be skipped, never drawn at width 0.
Paint _base({double width = kIconStrokeWidth}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = const Color(0xFF000000);

void main() {
  group('StrokeTaper weight — off by default (glyph balance)', () {
    test('the default floor never touches stroke weight, anywhere', () {
      // Weight modulation is per-contour; with a staggered exit it paints
      // neighbours at different weights and the glyph stops reading as one
      // drawing. So the shipped default is: don't.
      expect(StrokeTaper.kFloor, 1);
      for (var i = 0; i <= 20; i++) {
        expect(StrokeTaper.out(i / 20, 0.5), 1);
        expect(StrokeTaper.into(i / 20, 0.18), 1);
      }
    });

    test('exitWeight/entryWeight bypass the no-dot clamp when floor is 1', () {
      // The clamp is part of the taper, not a separate always-on thinning: a
      // sliver of ink keeps full weight and the fade removes it.
      expect(
        StrokeTaper.exitWeight(
            prog: 0.99,
            start: 0.5,
            floor: 1,
            visibleLength: 0.05,
            fullLength: 30),
        1,
      );
      expect(
        StrokeTaper.entryWeight(
            local: 0.01, end: 0.18, floor: 1, drawnLength: 0.05, fullLength: 30),
        1,
      );
    });

    test('lowering the floor turns the whole taper on, clamp included', () {
      expect(StrokeTaper.out(1, 0.5, 0.5), closeTo(0.5, 1e-9));
      expect(StrokeTaper.into(0, 0.18, 0.5), 0.5);
      final w = StrokeTaper.exitWeight(
          prog: 0.99, start: 0.5, floor: 0.5, visibleLength: 0.05, fullLength: 30);
      expect(w, lessThan(0.5)); // the clamp is under the floor, as documented
    });
  });

  group('StrokeTaper.out (the opt-in pen lift)', () {
    test('holds full weight until the taper point, then eases to the floor', () {
      expect(StrokeTaper.out(0, 0.5, 0.5), 1);
      expect(StrokeTaper.out(0.5, 0.5, 0.5), 1); // still full AT the taper point
      expect(StrokeTaper.out(0.75, 0.5, 0.5), lessThan(1));
      expect(StrokeTaper.out(0.75, 0.5, 0.5), greaterThan(0.5));
      expect(StrokeTaper.out(1, 0.5, 0.5), closeTo(0.5, 1e-9));
    });

    test('never rises, and never goes under the floor', () {
      var prev = 1.0;
      for (var i = 0; i <= 100; i++) {
        final w = StrokeTaper.out(i / 100, 0.5, 0.5);
        expect(w, lessThanOrEqualTo(prev + 1e-12));
        expect(w, greaterThanOrEqualTo(0.5 - 1e-12));
        prev = w;
      }
    });

    test('start >= 1 disables the taper (constant weight)', () {
      for (var i = 0; i <= 10; i++) {
        expect(StrokeTaper.out(i / 10, 1, 0.5), 1);
      }
    });
  });

  group('StrokeTaper.dissolve (the fade must last a real DURATION)', () {
    // The bug this group exists to prevent: a fade specified as "a quarter" of
    // the exit's PROGRESS. Progress is smoothstepped across the contour's
    // window, so that quarter lands exactly where the smoothstep moves fastest
    // and is over in 43 ms — under three frames at 60 Hz. On paper it was 25%;
    // on screen it was a cut.
    const morphMs = 640.0; // IconMotion.iconMorph
    const window = 0.45; // _kTrimExitWindow
    const len = 30.0;

    test('unSmooth inverts the window smoothstep', () {
      double smooth(double x) => 3 * x * x - 2 * x * x * x;
      for (final x in [0.0, 0.15, 0.4, 0.5, 0.72, 0.9, 1.0]) {
        expect(StrokeTaper.unSmooth(smooth(x)), closeTo(x, 1e-9));
      }
    });

    test('a span of PROGRESS would be under three frames — never use one', () {
      final horizon = StrokeTaper.dotHorizon(len);
      final x1 = StrokeTaper.unSmooth(horizon);
      final x0 = StrokeTaper.unSmooth(horizon - 0.25);
      final ms = (x1 - x0) * window * morphMs;
      expect(ms, lessThan(80)); // the measured 1.4.0 behaviour
    });

    test('a span of TIMELINE is the real thing — 160 ms, ~10 frames @60Hz', () {
      const plan = IconMorphPlan();
      final ms = plan.duration.inMilliseconds * (1 - plan.exitFade);
      expect(ms, greaterThanOrEqualTo(120)); // >= 7 frames @60Hz
    });

    test('alpha runs 1 → 0 across the span and stays 0 past the end', () {
      expect(StrokeTaper.dissolve(0.0, 0.35, 0.25), 1);
      // Exactly at the start: Cubic.transform is iterative, so it lands a hair
      // off 0 for a hair-off-0 input — opaque to any eye and any pixel.
      expect(StrokeTaper.dissolve(0.10, 0.35, 0.25), closeTo(1, 1e-5));
      expect(StrokeTaper.dissolve(0.225, 0.35, 0.25), closeTo(0.5, 0.02));
      expect(StrokeTaper.dissolve(0.35, 0.35, 0.25), 0);
      expect(StrokeTaper.dissolve(1.0, 0.35, 0.25), 0);
    });

    test('monotonic across the whole timeline', () {
      var prev = 1.0;
      for (var i = 0; i <= 400; i++) {
        final a = StrokeTaper.dissolve(i / 400, 0.35, 0.25);
        expect(a, lessThanOrEqualTo(prev + 1e-12));
        prev = a;
      }
    });

    test('the ink is gone by the dot horizon, mapped into timeline time', () {
      // What the painter computes for the first leaving contour (winStart 0).
      final horizonT = window * StrokeTaper.unSmooth(StrokeTaper.dotHorizon(len));
      expect(StrokeTaper.dissolve(horizonT, horizonT, 0.25), 0);
      // And it clears before the target assembles (flipStart 0.55).
      expect(horizonT, lessThan(0.55));
    });

    test('span <= 0 degrades to a hard cut at the end, not to always-visible',
        () {
      expect(StrokeTaper.dissolve(0.3, 0.35, 0), 1);
      expect(StrokeTaper.dissolve(0.35, 0.35, 0), 0);
    });
  });

  group('StrokeTaper.exitAlpha (the dissolve, anchored to geometry)', () {
    // The exit's visible length tracks (1 - prog), so a 30-unit contour with a
    // 2-unit stroke is dot-shaped (< 2 stroke-widths = 4 units) from prog 0.867.
    const len = 30.0;

    test('the ink is fully GONE before it could become a dot', () {
      final horizon = StrokeTaper.dotHorizon(len);
      expect(horizon, closeTo(1 - 4 / len, 1e-9));
      expect(StrokeTaper.exitAlpha(horizon, 0.75, len), 0);
      // Every frame from the horizon on draws nothing at all — this is the
      // property that makes a dot frame impossible, not merely unlikely.
      for (var p = horizon; p <= 1.0; p += 0.005) {
        expect(StrokeTaper.exitAlpha(p, 0.75, len), 0);
      }
    });

    test('while it is still a dot-sized stub, alpha is already zero', () {
      // The old clock-anchored fade left this stub at 30–70% alpha — the "final
      // dot" the owner kept seeing.
      for (final prog in [0.88, 0.9, 0.95, 0.99]) {
        final visible = len * (1 - prog);
        expect(visible, lessThan(StrokeTaper.kDotWidths * kIconStrokeWidth));
        expect(StrokeTaper.exitAlpha(prog, 0.75, len), 0);
        expect(StrokeTaper.fade(prog, 0.75), greaterThan(0)); // what it replaced
      }
    });

    test('the requested span is honoured, just slid earlier', () {
      final horizon = StrokeTaper.dotHorizon(len);
      expect(StrokeTaper.exitAlpha(horizon - 0.25, 0.75, len), 1); // opaque
      expect(StrokeTaper.exitAlpha(horizon - 0.125, 0.75, len),
          closeTo(0.5, 0.05)); // half way through the fade, half alpha
    });

    test('monotonic, and full alpha for the whole first stretch', () {
      var prev = 1.0;
      for (var i = 0; i <= 200; i++) {
        final a = StrokeTaper.exitAlpha(i / 200, 0.75, len);
        expect(a, lessThanOrEqualTo(prev + 1e-12));
        prev = a;
      }
      expect(StrokeTaper.exitAlpha(0, 0.75, len), 1);
      expect(StrokeTaper.exitAlpha(0.5, 0.75, len), 1);
    });

    test('a SHORT contour fades earlier, because it turns into a dot earlier',
        () {
      // 6 units of a 2-unit stroke: dot-shaped almost immediately, so the
      // horizon is capped at half its length and it leaves in its first half.
      expect(StrokeTaper.dotHorizon(6), closeTo(0.5, 1e-9));
      expect(StrokeTaper.exitAlpha(0.6, 0.75, 6), 0);
      expect(StrokeTaper.exitAlpha(0.1, 0.75, 6), 1);
    });

    test('an authored dot fades over its own second half, never deleted', () {
      const dot = 0.01;
      expect(StrokeTaper.dotHorizon(dot), closeTo(0.5, 1e-9));
      expect(StrokeTaper.exitAlpha(0, 0.75, dot), 1); // present at rest
      expect(StrokeTaper.exitAlpha(0.5, 0.75, dot), 0);
    });
  });

  group('StrokeTaper.fade (the clock-anchored fade, kept for custom effects)',
      () {
    test('opaque until the fade point, then out to nothing by the end', () {
      expect(StrokeTaper.fade(0, 0.75), 1);
      expect(StrokeTaper.fade(0.75, 0.75), 1); // still opaque AT the fade point
      expect(StrokeTaper.fade(0.875, 0.75), lessThan(1));
      expect(StrokeTaper.fade(0.875, 0.75), greaterThan(0));
      expect(StrokeTaper.fade(1, 0.75), closeTo(0, 1e-9));
    });

    test('never rises', () {
      var prev = 1.0;
      for (var i = 0; i <= 100; i++) {
        final a = StrokeTaper.fade(i / 100, 0.75);
        expect(a, lessThanOrEqualTo(prev + 1e-12));
        prev = a;
      }
    });

    test('start >= 1 disables the fade (removal by length alone)', () {
      expect(StrokeTaper.fade(1, 1), 1);
    });
  });

  group('StrokeTaper.into (the opt-in nib press-down)', () {
    test('starts at the floor and reaches full weight by the ramp end', () {
      expect(StrokeTaper.into(0, 0.2, 0.5), 0.5);
      expect(StrokeTaper.into(0.1, 0.2, 0.5), greaterThan(0.5));
      expect(StrokeTaper.into(0.1, 0.2, 0.5), lessThan(1));
      expect(StrokeTaper.into(0.2, 0.2, 0.5), 1);
      expect(StrokeTaper.into(1, 0.2, 0.5), 1); // and holds it for the draw
    });

    test('end <= 0 disables the ramp (full weight from the first pixel)', () {
      expect(StrokeTaper.into(0, 0, 0.5), 1);
    });
  });

  group('StrokeTaper.lengthClamp (the no-dot safety net)', () {
    test('full weight while the stroke is comfortably longer than it is wide',
        () {
      expect(StrokeTaper.lengthClamp(30, 30), 1);
      expect(StrokeTaper.lengthClamp(6, 30), 1); // exactly 3x the 2-unit width
    });

    test('ink is never wider than a third of the length it has left', () {
      // Below the ratio the weight tracks the remaining length, so a shrinking
      // stub can never render as a round-cap blob.
      for (final visible in [3.0, 1.5, 0.6, 0.1]) {
        final w = StrokeTaper.lengthClamp(visible, 30);
        expect(w * kIconStrokeWidth * StrokeTaper.kLengthRatio,
            lessThanOrEqualTo(visible + 1e-9));
      }
      expect(StrokeTaper.lengthClamp(0, 30), 0);
    });

    test('an AUTHORED dot keeps full weight and shrinks out, not erased', () {
      // Icons author dots as a hair-length line; they must read as a full-weight
      // round cap while present — referencing their own length, not the ratio.
      const dot = 0.01;
      expect(StrokeTaper.lengthClamp(dot, dot), 1);
      expect(StrokeTaper.lengthClamp(dot / 2, dot), closeTo(0.5, 1e-9));
    });
  });

  group('StrokeTaper.weighted (what actually reaches the canvas)', () {
    test('full weight returns the base paint itself — no per-frame allocation',
        () {
      final base = _base();
      expect(identical(StrokeTaper.weighted(base, 1), base), isTrue);
    });

    test('spent ink returns null so the caller draws NOTHING', () {
      // The whole point: never hand Skia strokeWidth 0, which is hairline mode.
      expect(StrokeTaper.weighted(_base(), 0), isNull);
      expect(StrokeTaper.weighted(_base(), 1e-4), isNull);
    });

    test('fully faded returns null too, at any weight', () {
      expect(StrokeTaper.weighted(_base(), 1, alpha: 0), isNull);
      expect(StrokeTaper.weighted(_base(), 0.5, alpha: 0), isNull);
    });

    test('a fade at full weight keeps the width and only drops alpha', () {
      final p = StrokeTaper.weighted(_base(), 1, alpha: 0.4)!;
      expect(p.strokeWidth, closeTo(kIconStrokeWidth, 1e-6));
      expect(p.color.a, closeTo(0.4, 0.01));
    });

    test('weight and fade compound — a thinned, dissolving stroke', () {
      final p = StrokeTaper.weighted(_base(), 0.5, alpha: 0.5)!;
      expect(p.strokeWidth, closeTo(1, 1e-6));
      expect(p.color.a, closeTo(0.5, 0.01));
    });

    test('a returned paint always has a real, renderable width', () {
      // (Paint stores stroke width as a float32, so read-back is compared with a
      // single-precision tolerance, not exactly.)
      for (var i = 1; i <= 1000; i++) {
        final p = StrokeTaper.weighted(_base(), i / 1000);
        if (p == null) continue;
        expect(p.strokeWidth, greaterThanOrEqualTo(StrokeTaper.kMinWidth - 1e-6));
      }
    });

    test('below the minimum width it holds the floor and pays in alpha', () {
      final base = _base();
      // 0.1 * 2 = 0.2 units — under the 0.35 floor.
      final p = StrokeTaper.weighted(base, 0.1)!;
      expect(p.strokeWidth, closeTo(StrokeTaper.kMinWidth, 1e-6));
      expect(p.color.a, lessThan(1));
      expect(p.color.a, greaterThan(0));
      // Above the floor the width does the work and alpha stays untouched.
      final q = StrokeTaper.weighted(base, 0.5)!;
      expect(q.strokeWidth, closeTo(1, 1e-9));
      expect(q.color.a, 1);
    });

    test('carries the base stroke geometry over', () {
      final p = StrokeTaper.weighted(_base(), 0.5)!;
      expect(p.style, PaintingStyle.stroke);
      expect(p.strokeCap, StrokeCap.round);
      expect(p.strokeJoin, StrokeJoin.round);
    });
  });

  group('IconMorphPlan taper knobs', () {
    test('defaults: no thinning at all, dissolve over the last quarter', () {
      const plan = IconMorphPlan();
      expect(plan.taperFloor, 1); // weight is never touched
      expect(plan.exitFade, 0.75); // alpha is the whole vanish
      expect(plan.exitTaper, 0.5); // present but inert while the floor is 1
      expect(plan.assembleTaper, 0.18);
    });

    test('the knobs take part in value equality — a tuning change repaints', () {
      const plan = IconMorphPlan();
      expect(plan.copyWith(exitTaper: 0.5), plan);
      expect(plan.copyWith(exitTaper: 0.8), isNot(plan));
      expect(plan.copyWith(exitFade: 0.6), isNot(plan));
      expect(plan.copyWith(taperFloor: 0.7), isNot(plan));
      expect(plan.copyWith(assembleTaper: 0.4), isNot(plan));
      expect(plan.copyWith(exitTaper: 0.8).hashCode, isNot(plan.hashCode));
      expect(plan.copyWith(exitFade: 0.6).hashCode, isNot(plan.hashCode));
      expect(plan.copyWith(taperFloor: 0.7).hashCode, isNot(plan.hashCode));
      expect(plan.copyWith(assembleTaper: 0.4).hashCode, isNot(plan.hashCode));
      // The field list is past Object.hash's 20-argument ceiling; hashAll must
      // still separate a change in the LAST field.
      expect(plan.copyWith(flipTarget: true).hashCode, isNot(plan.hashCode));
    });
  });
}
