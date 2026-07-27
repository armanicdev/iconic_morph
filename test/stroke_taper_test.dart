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
  group('StrokeTaper.out (the pen lift)', () {
    test('holds full weight until the taper point, then falls to nothing', () {
      expect(StrokeTaper.out(0, 0.5), 1);
      expect(StrokeTaper.out(0.5, 0.5), 1); // still full AT the taper point
      expect(StrokeTaper.out(0.75, 0.5), lessThan(1));
      expect(StrokeTaper.out(0.75, 0.5), greaterThan(0));
      expect(StrokeTaper.out(1, 0.5), closeTo(0, 1e-9)); // gone when length is
    });

    test('never rises — weight only ever runs out', () {
      var prev = 1.0;
      for (var i = 0; i <= 100; i++) {
        final w = StrokeTaper.out(i / 100, 0.5);
        expect(w, lessThanOrEqualTo(prev + 1e-12));
        prev = w;
      }
    });

    test('start >= 1 disables the taper (pre-1.1 constant weight)', () {
      for (var i = 0; i <= 10; i++) {
        expect(StrokeTaper.out(i / 10, 1), 1);
      }
    });
  });

  group('StrokeTaper.into (the nib pressing down)', () {
    test('starts at nothing and reaches full weight by the ramp end', () {
      expect(StrokeTaper.into(0, 0.2), 0);
      expect(StrokeTaper.into(0.1, 0.2), greaterThan(0));
      expect(StrokeTaper.into(0.1, 0.2), lessThan(1));
      expect(StrokeTaper.into(0.2, 0.2), 1);
      expect(StrokeTaper.into(1, 0.2), 1); // and holds it for the whole draw
    });

    test('end <= 0 disables the ramp (full weight from the first pixel)', () {
      expect(StrokeTaper.into(0, 0), 1);
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
    test('defaults taper the exit at the halfway point and ramp the entrance',
        () {
      const plan = IconMorphPlan();
      expect(plan.exitTaper, 0.5);
      expect(plan.assembleTaper, 0.18);
    });

    test('the knobs take part in value equality — a tuning change repaints', () {
      const plan = IconMorphPlan();
      expect(plan.copyWith(exitTaper: 0.5), plan);
      expect(plan.copyWith(exitTaper: 0.8), isNot(plan));
      expect(plan.copyWith(assembleTaper: 0.4), isNot(plan));
      expect(plan.copyWith(exitTaper: 0.8).hashCode, isNot(plan.hashCode));
      expect(plan.copyWith(assembleTaper: 0.4).hashCode, isNot(plan.hashCode));
      // The field list is past Object.hash's 20-argument ceiling; hashAll must
      // still separate a change in the LAST field.
      expect(plan.copyWith(flipTarget: true).hashCode, isNot(plan.hashCode));
    });
  });
}
