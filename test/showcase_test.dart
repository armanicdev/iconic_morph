import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/iconic_morph.dart';

/// Proves the batteries-included path works end-to-end: the THREE bundled demo
/// icons (user → face → lock) load from the package's own asset bundle and the
/// morph paints, using only the public `package:iconic_morph/iconic_morph.dart` API.
void main() {
  testWidgets('bundled MorphIcons load + IconicMorph paints (user→face→lock)',
      (tester) async {
    for (final pair in const [
      (MorphIcons.user, MorphIcons.face),
      (MorphIcons.face, MorphIcons.lock),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: IconicMorph(pair.$1, pair.$2, size: 64),
          ),
        ),
      );
      // Let the async geometry load + the autoplay morph settle.
      await tester.pumpAndSettle();
      expect(find.byType(IconicMorph), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('IconImage renders a bundled icon statically', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: IconImage.asset(MorphIcons.lock, size: 48)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('MorphIcons.chain is the three demo glyphs in order', () {
    expect(MorphIcons.chain, [MorphIcons.user, MorphIcons.face, MorphIcons.lock]);
    expect(MorphIcons.user, contains('user-01.svg'));
    expect(MorphIcons.face, contains('face-id.svg'));
    expect(MorphIcons.lock, contains('lock-01.svg'));
  });
}
