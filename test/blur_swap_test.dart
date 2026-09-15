import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/iconic_morph.dart';

void main() {
  Widget host(String icon) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IconicBlurSwap(icon, size: 48, color: const Color(0xFF000000)),
        ),
      );

  test('the timing law: outgoing gone by 55%, incoming from 25%, ends crisp',
      () {
    expect(BlurSwapFrame.out(0), (alpha: 1.0, focus: 1.0, scale: 1.0));
    expect(BlurSwapFrame.out(0.55).alpha, 0);
    expect(BlurSwapFrame.out(1).alpha, 0);
    expect(BlurSwapFrame.inn(0.25).alpha, 0);
    expect(BlurSwapFrame.inn(0.25).focus, 0);
    final end = BlurSwapFrame.inn(1);
    expect(end.alpha, 1);
    expect(end.focus, 1);
    expect(end.scale, closeTo(1, 1e-6));
    // The overlap: at 40% both glyphs are on screen, neither crisp.
    final a = BlurSwapFrame.out(0.4);
    final b = BlurSwapFrame.inn(0.4);
    expect(a.alpha, greaterThan(0));
    expect(b.alpha, greaterThan(0));
    expect(a.focus, lessThan(1));
    expect(b.focus, lessThan(1));
  });

  testWidgets('a changed icon plays one swap and settles on the new glyph',
      (tester) async {
    await IconGeometry.load(MorphIcons.user);
    await IconGeometry.load(MorphIcons.lock);
    await tester.pumpWidget(host(MorphIcons.user));
    await tester.pump();
    expect(find.byType(IconicBlurSwap), findsOneWidget);

    await tester.pumpWidget(host(MorphIcons.lock));
    await tester.pump(IconMotion.iconSwap ~/ 2);
    expect(tester.takeException(), isNull);
    await tester.pump(IconMotion.iconSwap);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion snaps to the new icon without a clock',
      (tester) async {
    await IconGeometry.load(MorphIcons.user);
    await IconGeometry.load(MorphIcons.lock);
    Widget reduced(String icon) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(icon),
        );
    await tester.pumpWidget(reduced(MorphIcons.user));
    await tester.pump();
    await tester.pumpWidget(reduced(MorphIcons.lock));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
