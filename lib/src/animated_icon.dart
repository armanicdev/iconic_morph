import 'package:flutter/widgets.dart';

import 'icon_image.dart';
import 'motion.dart';

import 'icon_effect.dart';
import 'icon_geometry.dart';

/// Imperative handle to replay a [IconicAnimatedIcon] from a parent (a button tap,
/// a list-row appear, a "replay" control). Call [play] to (re)start the effect
/// from the beginning — interrupt-safe, so rapid taps restart cleanly. [stop]
/// settles the icon to its rest frame.
class IconicAnimatedIconController extends ChangeNotifier {
  int _epoch = 0;
  bool _stopFlag = false;

  /// Bumped each [play]; the widget listens and restarts on change.
  int get epoch => _epoch;
  bool get stopRequested => _stopFlag;

  void play() {
    _stopFlag = false;
    _epoch++;
    notifyListeners();
  }

  void stop() {
    _stopFlag = true;
    _epoch++;
    notifyListeners();
  }
}

/// An icon that animates via a [IconEffect] (3D spin, trim draw-on,
/// breathe, and more). Pass an asset path and an effect; the widget handles
/// geometry loading, caching, and animation control.
///
/// Performance and correctness:
///  * Geometry is parsed and sampled once per asset and cached ([IconGeometry]);
///    the painter is driven by the controller so only its layer repaints (no
///    widget rebuild), isolated in a [RepaintBoundary].
///  * Until the geometry resolves, a static [IconImage] of the same asset is
///    shown — so the first frame is never blank or a different shape.
///  * Reduced-motion (OS accessibility setting) replaces animation with the
///    effect's settled frame rather than simply skipping or speeding it up.
class IconicAnimatedIcon extends StatefulWidget {
  const IconicAnimatedIcon(
    this.asset, {
    super.key,
    required this.effect,
    this.size = 24,
    this.color,
    this.controller,
    this.autoplay = true,
    this.timeScale = 1,
    this.semanticLabel,
  });

  /// Asset path, e.g. a bundled `MorphIcons.*` value or your own SVG asset path.
  final String asset;

  /// The animation strategy.
  final IconEffect effect;

  final double size;

  /// Tint color. Null resolves to the ambient [DefaultTextStyle] color.
  final Color? color;

  /// Optional external trigger for replay/stop.
  final IconicAnimatedIconController? controller;

  /// Play automatically once geometry is ready (looping effects repeat). When
  /// false the icon sits at the effect's rest frame until [controller.play].
  final bool autoplay;

  /// Stretches the effect's duration (1 = real time, 6 = 6× slow motion). Lets a
  /// gallery inspect the motion frame by frame without changing the effect.
  final double timeScale;

  final String? semanticLabel;

  @override
  State<IconicAnimatedIcon> createState() => _IconicAnimatedIconState();
}

class _IconicAnimatedIconState extends State<IconicAnimatedIcon>
    with SingleTickerProviderStateMixin {
  // Built eagerly in initState, not lazily: before geometry resolves, nothing
  // touches _ac, so a `late` init would defer construction until dispose() —
  // building a Ticker during unmounting crashes. Creating it here ensures dispose
  // only ever disposes an already-constructed controller.
  late final AnimationController _ac;
  IconGeometry? _geom;

  /// Effect duration stretched by [IconicAnimatedIcon.timeScale] (slow motion).
  Duration get _scaledDuration => Duration(
        microseconds:
            (widget.effect.duration.inMicroseconds * widget.timeScale).round(),
      );
  bool _kicked = false; // whether we've applied the initial autoplay/rest

  // A play() or stop() call that arrived before geometry resolved. Applied in
  // [_applyInitial] so commands fired during the async load aren't silently lost.
  // null = no pending command.
  bool? _pendingPlay;

  // Cached reduce-motion value, read in didChangeDependencies. Async callbacks
  // and listeners must NOT call IconMotion.reduced(context) directly: an element can
  // be deactivated (scrolled offscreen) while still mounted, and an inherited
  // widget lookup on a deactivated element throws.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: _scaledDuration);
    _geom = IconGeometry.peek(widget.asset);
    if (_geom == null) _load();
    widget.controller?.addListener(_onController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery (reduced-motion) is valid here — read + cache it so async/
    // listener callbacks never do an ancestor lookup on a deactivated element.
    final was = _reduceMotion;
    _reduceMotion = IconMotion.reduced(context);
    _applyInitial();
    // Handle a runtime change to the OS reduce-motion setting: _applyInitial only
    // runs once, so without this check a looping effect would keep animating after
    // the user enables reduce-motion mid-session.
    if (_kicked && _geom != null && was != _reduceMotion) {
      if (_reduceMotion) {
        _ac
          ..stop()
          ..value = widget.effect.restValue;
      } else if (widget.autoplay || _ac.isAnimating) {
        _start();
      }
    }
  }

  @override
  void didUpdateWidget(IconicAnimatedIcon old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }

    // IconEffect is @immutable with no == override, so use identity comparison.
    // A parent typically holds effects as const fields, so a changed instance
    // means a genuinely different effect.
    final effectChanged = !identical(old.effect, widget.effect);
    final speedChanged = old.effect.duration != widget.effect.duration ||
        old.timeScale != widget.timeScale;
    if (effectChanged || speedChanged) {
      _ac.duration = _scaledDuration;
    }

    if (old.asset != widget.asset) {
      _geom = IconGeometry.peek(widget.asset);
      _kicked = false;
      if (_geom == null) {
        _load();
      } else {
        _applyInitial();
      }
      return; // an asset swap re-settles from scratch — nothing else to reconcile
    }

    if (effectChanged) {
      // The painter picks up the new effect, but the CONTROLLER would otherwise
      // stay parked at its old value/mode (a finished forward() stuck at 1, a
      // now-looping effect that never calls repeat(), a stale restValue). Re-drive
      // it to match the new effect.
      if (_geom == null) return; // _load/_applyInitial will settle it
      if (_reduceMotion) {
        _ac
          ..stop()
          ..value = widget.effect.restValue;
      } else if (_ac.isAnimating || widget.autoplay) {
        _start();
      } else {
        _ac
          ..stop()
          ..value = widget.effect.restValue;
      }
    } else if (speedChanged &&
        widget.effect.loops &&
        _ac.isAnimating &&
        !_reduceMotion) {
      // Apply a new speed to an in-flight loop immediately.
      _start();
    }
  }

  Future<void> _load() async {
    // Snapshot the asset across the await: if it swaps mid-load (rapid icon
    // change in a list), the stale load must NOT overwrite the newer geometry —
    // a later _load for the current asset owns it.
    final asset = widget.asset;
    final g = await IconGeometry.load(asset);
    if (!mounted || asset != widget.asset) return;
    setState(() => _geom = g);
    _applyInitial();
  }

  /// First settle after geometry is ready: autoplay or rest, honoring motion.
  void _applyInitial() {
    if (_geom == null || _kicked) return;
    _kicked = true;
    // A controller play()/stop() that arrived before geometry was ready takes
    // precedence over autoplay/rest.
    final pending = _pendingPlay;
    if (pending != null) {
      _pendingPlay = null;
      if (_reduceMotion || !pending) {
        _ac.value = widget.effect.restValue;
      } else {
        _start();
      }
      return;
    }
    if (_reduceMotion) {
      _ac.value = widget.effect.restValue;
    } else if (widget.autoplay) {
      _start();
    } else {
      _ac.value = widget.effect.restValue;
    }
  }

  void _start() {
    if (widget.effect.loops) {
      _ac.repeat(reverse: widget.effect.autoReverse);
    } else {
      _ac.forward(from: 0);
    }
  }

  void _onController() {
    if (!mounted) return;
    final c = widget.controller!;
    if (_geom == null) {
      // Geometry not yet loaded — remember the intent so _applyInitial honors it
      // once geometry resolves (a play() fired during loading would otherwise be
      // silently lost).
      _pendingPlay = !c.stopRequested;
      return;
    }
    if (c.stopRequested) {
      _ac.stop();
      _ac.value = widget.effect.restValue;
      return;
    }
    if (_reduceMotion) {
      _ac.value = widget.effect.restValue;
      return;
    }
    _start();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    final geom = _geom;

    final Widget child = geom == null
        ? IconImage.asset(widget.asset, size: widget.size, color: color)
        : RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: IconEffectPainter(
                effect: widget.effect,
                geom: geom,
                color: color,
                progress: _ac,
              ),
            ),
          );

    if (widget.semanticLabel == null) return child;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: ExcludeSemantics(child: child),
    );
  }
}
