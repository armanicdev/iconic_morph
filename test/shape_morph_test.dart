import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/iconic_morph.dart';

/// Two synthetic SIBLING icons sharing an identical two-line "frame":
///  * A carries a face-ish set — two short "eyes" and a long "smile" curve.
///  * B carries a verdict-ish set — a "stem" line and a hair-length "dot".
const String _svgA =
    '<svg viewBox="0 0 24 24"><path d="M2 2H22M2 22H22'
    'M8 8v2M16 8v2M8 16c2 2 6 2 8 0"/></svg>';
const String _svgB =
    '<svg viewBox="0 0 24 24"><path d="M2 2H22M2 22H22'
    'M12 7v6M12 16h.01"/></svg>';

void main() {
  final a = IconGeometry.parse(_svgA);
  final b = IconGeometry.parse(_svgB);

  group('ShapeMorphGeometry.build', () {
    test('identical contours are detected as still chrome, not animated', () {
      final g = ShapeMorphGeometry.build(a, b, const ShapeMorphSpec());
      // A has 5 contours (2 frame + 2 eyes + smile), B has 4 (2 frame +
      // stem + dot). The two frame lines match on both sides, so the moving
      // sets partition the REMAINDER: 3 from A, 2 from B.
      expect(
        g.pairs.length * 2 + g.exits.length + g.enters.length,
        (5 - 2) + (4 - 2),
      );
      expect(g.still, isNot(equals(Path())));
      expect(g.viewBox, 24);
    });

    test('explicit anchors pair the named features; the rest exits', () {
      final g = ShapeMorphGeometry.build(
        a,
        b,
        const ShapeMorphSpec(
          autoPair: false,
          // smile (centroid ≈ (12, 16.7)) → dot (12, 16).
          pairs: [(Offset(12, 17), Offset(12, 16))],
        ),
      );
      expect(g.pairs.length, 1);
      // The two eyes leave; the stem arrives.
      expect(g.exits.length, 2);
      expect(g.enters.length, 1);
      // Paired lists are resampled to a common count.
      expect(g.pairs.single.from.length, g.pairs.single.to.length);
      // The pair really is smile → dot: its target collapses near (12, 16).
      for (final p in g.pairs.single.to) {
        expect((p - const Offset(12, 16)).distance, lessThan(0.5));
      }
    });

    test('autoPair pairs the dominant remainder on asymmetric counts', () {
      final g = ShapeMorphGeometry.build(a, b, const ShapeMorphSpec());
      // 3 movers from A, 2 targets in B → 2 pairs + 1 exit + 0 enters.
      expect(g.pairs.length, 2);
      expect(g.exits.length, 1);
      expect(g.enters, isEmpty);
    });

    test('a double-booked explicit anchor is skipped, not applied twice', () {
      final g = ShapeMorphGeometry.build(
        a,
        b,
        const ShapeMorphSpec(
          autoPair: false,
          // Both entries resolve to the SAME smile/dot pair — the second must
          // be dropped (its contours are already consumed by the first, so
          // the anchors re-resolve to different remaining contours instead).
          pairs: [
            (Offset(12, 17), Offset(12, 16)),
            (Offset(12, 17), Offset(12, 16)),
          ],
        ),
      );
      // First entry pairs smile→dot; the second's anchors then resolve to the
      // nearest REMAINING contours (an eye → the stem) — 2 pairs, no dupes.
      expect(g.pairs.length, 2);
      expect(g.exits.length, 1);
    });
  });

  group('ShapeMorphPainter', () {
    testWidgets('paints every phase without exception and honours the clock',
        (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      final geom = ShapeMorphGeometry.build(a, b, const ShapeMorphSpec());

      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            size: const Size.square(64),
            painter: ShapeMorphPainter(
              geometry: geom,
              animation: controller,
              color: const Color(0xFF0000FF),
              colorEnd: const Color(0xFF00FF00),
              chromeColor: const Color(0xFF000000),
              chromeColorEnd: const Color(0xFF888888),
            ),
          ),
        ),
      );
      for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        controller.value = v;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'clock at $v');
      }
    });

    testWidgets('a dedicated colorCurve paints every phase exception-free',
        (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      const spec = ShapeMorphSpec(colorCurve: Curves.easeOutCubic);
      final geom = ShapeMorphGeometry.build(a, b, spec);

      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            size: const Size.square(64),
            painter: ShapeMorphPainter(
              geometry: geom,
              animation: controller,
              spec: spec,
              color: const Color(0xFF0000FF),
              colorEnd: const Color(0xFF00FF00),
            ),
          ),
        ),
      );
      for (final v in [0.0, 0.3, 0.7, 1.0]) {
        controller.value = v;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'ink clock at $v');
      }
    });
  });

}
