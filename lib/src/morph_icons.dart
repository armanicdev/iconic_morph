/// Demo icons bundled with the package — three glyphs that work out of the box
/// for morphing examples (`user → face → lock`). No setup required:
///
/// ```dart
/// IconicMorph(MorphIcons.user, MorphIcons.face)
/// ```
///
/// The engine is icon-agnostic; these are only bundled so demos run immediately.
/// Pass any SVG via your own asset path or as a raw string using
/// `IconicMorph.svg` / `IconImage.svg`.
///
/// Each value is a package-asset path that `rootBundle` resolves automatically
/// from the consuming app's bundle.
abstract final class MorphIcons {
  static const String _base = 'packages/iconic_morph/assets/icons';

  /// A person glyph — the morph chain's start.
  static const String user = '$_base/user-01.svg';

  /// A face-ID glyph — the chain's middle (smile is the hero line).
  static const String face = '$_base/face-id.svg';

  /// A padlock glyph — the chain's end (shackle is the hero line).
  static const String lock = '$_base/lock-01.svg';

  /// The bundled demo chain, in order: user → face → lock.
  static const List<String> chain = [user, face, lock];
}
