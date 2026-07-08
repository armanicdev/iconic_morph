import 'package:flutter/widgets.dart';
import 'package:iconic_morph/iconic_morph.dart';

/// A tiny, **no-Material** showcase for `iconic_morph` — the bundled
/// `user → face → lock` morph, a static icon, and a 3D unlock spin. Tap any card
/// to replay. Everything here uses only `package:iconic_morph/iconic_morph.dart` and
/// the three batteries-included [MorphIcons].
void main() => runApp(const IconMorphExampleApp());

const _bg = Color(0xFF0E1116);
const _fg = Color(0xFFE9EDF2);
const _accent = Color(0xFF6AA2FF);

class IconMorphExampleApp extends StatelessWidget {
  const IconMorphExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'iconic_morph',
      color: _accent,
      // No Material — a plain colored root + a default text style the icons
      // inherit their tint from (IconImage/morph read DefaultTextStyle.color).
      builder: (context, _) => Container(
        color: _bg,
        child: const DefaultTextStyle(
          style: TextStyle(color: _fg, fontSize: 15, decoration: TextDecoration.none),
          child: _Showcase(),
        ),
      ),
    );
  }
}

class _Showcase extends StatelessWidget {
  const _Showcase();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'iconic_morph',
                style: TextStyle(color: _fg, fontSize: 28, decoration: TextDecoration.none),
              ),
              const SizedBox(height: 6),
              const Text(
                'path-level icon animation · zero dependencies',
                style: TextStyle(color: Color(0xFF8A93A0), fontSize: 13, decoration: TextDecoration.none),
              ),
              const SizedBox(height: 28),
              _MorphCard(
                from: MorphIcons.user,
                to: MorphIcons.face,
                label: 'User → Face',
              ),
              const SizedBox(height: 16),
              _MorphCard(
                from: MorphIcons.face,
                to: MorphIcons.lock,
                label: 'Face → Lock',
              ),
              const SizedBox(height: 16),
              _SpinCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable morph card: the [from] glyph morphs into [to] on load and on tap.
class _MorphCard extends StatefulWidget {
  const _MorphCard({required this.from, required this.to, required this.label});

  final String from;
  final String to;
  final String label;

  @override
  State<_MorphCard> createState() => _MorphCardState();
}

class _MorphCardState extends State<_MorphCard> {
  final _c = IconicAnimatedIconController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      label: widget.label,
      onTap: _c.play,
      child: IconicMorph(
        widget.from,
        widget.to,
        size: 96,
        color: _fg,
        controller: _c,
      ),
    );
  }
}

/// A tappable card: the lock does a constant-stroke 3D unlock spin on tap.
class _SpinCard extends StatefulWidget {
  @override
  State<_SpinCard> createState() => _SpinCardState();
}

class _SpinCardState extends State<_SpinCard> {
  final _c = IconicAnimatedIconController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      label: 'Lock · 3D unlock spin',
      onTap: _c.play,
      child: IconicAnimatedIcon(
        MorphIcons.lock,
        size: 96,
        color: _fg,
        effect: const IconSpin3D.unlock(),
        controller: _c,
        autoplay: false,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF222A35)),
        ),
        child: Column(
          children: [
            SizedBox(height: 96, width: 96, child: Center(child: child)),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: _fg, fontSize: 14, decoration: TextDecoration.none)),
            const SizedBox(height: 2),
            const Text('tap to replay', style: TextStyle(color: Color(0xFF6A737D), fontSize: 12, decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }
}
