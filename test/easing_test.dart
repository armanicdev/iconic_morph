import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/iconic_morph.dart';

void main() {
  group('IconicSpringCurve', () {
    test('is a valid Curve: 0 at 0, 1 at 1, strictly monotone at defaults', () {
      const c = IconicSpringCurve();
      expect(c.transform(0), 0);
      expect(c.transform(1), 1);
      var prev = 0.0;
      for (var i = 1; i <= 100; i++) {
        final v = c.transform(i / 100);
        expect(v, greaterThan(prev), reason: 'not monotone at t=${i / 100}');
        prev = v;
      }
    });

    test('has genuine launch velocity and a silk settle (the snap profile)',
        () {
      const c = IconicSpringCurve();
      // Peak velocity up front: well past linear early on…
      expect(c.transform(0.25), greaterThan(0.55));
      // …most of the travel closed by half-time…
      expect(c.transform(0.5), greaterThan(0.85));
      // …and the last tenth is a settle, not a rush.
      expect(1 - c.transform(0.9), lessThan(0.02));
    });

    test('velocity under omega never overshoots', () {
      const c = IconicSpringCurve(omega: 9, velocity: 4);
      for (var i = 0; i <= 100; i++) {
        expect(c.transform(i / 100), lessThanOrEqualTo(1.0000001));
      }
    });

    test('a spring that cannot reach its target by t=1 asserts loudly', () {
      // velocity so negative the normalization flips sign — a silent flip
      // would invert the whole curve.
      expect(
        () => const IconicSpringCurve(omega: 0.5, velocity: -5).transform(0.5),
        throwsAssertionError,
      );
    });

    test('value equality keys on the tuning', () {
      expect(const IconicSpringCurve(), const IconicSpringCurve());
      expect(
        const IconicSpringCurve(),
        isNot(equals(const IconicSpringCurve(omega: 9))),
      );
      expect(
        const IconicSpringCurve().hashCode,
        const IconicSpringCurve().hashCode,
      );
    });
  });

  group('easing options on the specs', () {
    test('ShapeMorphSpec defaults to snap; curves participate in equality', () {
      expect(const ShapeMorphSpec().curve, IconicEase.snap);
      expect(const ShapeMorphSpec().colorCurve, isNull);
      expect(
        const ShapeMorphSpec(),
        isNot(equals(const ShapeMorphSpec(curve: IconicEase.glide))),
      );
      expect(
        const ShapeMorphSpec(),
        isNot(equals(const ShapeMorphSpec(colorCurve: Curves.easeOutCubic))),
      );
    });

    test('IconMorphPlan keeps the signature flight ease as its default', () {
      expect(const IconMorphPlan().curve, IconicEase.flight);
      // The default is bit-identical to the pre-1.8.0 hardcoded worm ease.
      expect(IconicEase.flight, const Cubic(0.25, 1.0, 0.5, 1.0));
      expect(
        const IconMorphPlan(),
        isNot(equals(const IconMorphPlan(curve: IconicEase.snap))),
      );
      expect(
        const IconMorphPlan().copyWith(curve: IconicEase.snap).curve,
        IconicEase.snap,
      );
    });
  });
}
