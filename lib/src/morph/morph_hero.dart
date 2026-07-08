import 'package:flutter/widgets.dart';

import '../icon_image.dart';
import '../motion.dart';

import '../icon_effect.dart';
import '../icon_geometry.dart';
import '../animated_icon.dart';
import 'icon_morph.dart';
import 'morph_plan.dart';

/// A **persistent, "alive" hero glyph** that lives ONCE across screens/steps and
/// AUTO-TRANSITIONS between icons without ever remounting — so there is no
/// flicker, stutter, or replay-from-scratch when the surrounding page changes.
///
/// Lift ONE of these into persistent chrome (a fixed anchor) and just change its
/// [icon] as the flow advances; it runs a small state machine:
///  • **intro** — on first appearance, plays [intro] on [icon] (e.g. draw → spin).
///  • **morph** — when [icon] changes, morphs the shown glyph → the new one in
///    place via [IconicMorph] (using the [plan] supplied for that target).
///  • **idle** — at rest between transitions, loops [idle] (e.g. a subtle 3D
///    tilt) so the glyph feels alive. Null [idle] = still.
///
/// Because the SAME element persists across page transitions, sliding content can
/// move underneath while the glyph morphs in place. Reduced-motion collapses the
/// machine to "show the target, no motion". Geometry is pre-warmed so a morph or
/// idle never flashes a static fallback.
class IconicMorphHero extends StatefulWidget {
  const IconicMorphHero(
    this.icon, {
    super.key,
    this.plan = const IconMorphPlan(),
    this.reverse = false,
    this.size = 24,
    this.color,
    this.intro,
    this.idle,
    this.idleBuilder,
    this.semanticLabel,
    this.motionBlur = false,
    this.onSettled,
    this.actionEffect,
    this.actionController,
    this.restBuilder,
  });

  /// The icon the hero should currently be (or morph toward). Change it to drive
  /// a transition; the hero handles the rest.
  final String icon;

  /// Plan used for the morph INTO [icon] (e.g. a `heroAnchor` on the smile when
  /// morphing into a face). Read at the moment [icon] changes.
  ///
  /// When [reverse] is true this is the FORWARD plan of the opposite transition —
  /// the morph is played time-reversed (see [reverse]), so a "go back" reuses the
  /// exact forward morph backward instead of needing its own mirrored plan.
  final IconMorphPlan plan;

  /// Play the morph INTO [icon] as a TIME-REVERSED forward morph: the hero hands
  /// [IconicMorph] the forward pair (target→current) with [IconicMorph.reverse],
  /// so the worm traces the forward flight backward and lands on [icon]. Use for
  /// "back" navigation — the reverse of a transition is its forward morph rewound,
  /// guaranteeing it's exactly as smooth as the forward one. Read at morph start.
  final bool reverse;

  final double size;

  /// Tint. Null resolves to the ambient [DefaultTextStyle] color.
  final Color? color;

  /// Effect for the FIRST appearance. Null = appear straight into idle/still.
  final IconEffect? intro;

  /// Looping "alive" effect at rest between transitions. Null = still.
  final IconEffect? idle;

  /// Per-icon idle override: given the resting icon, return its idle effect (e.g.
  /// `faceId` blinks while others tilt). Wins over [idle] when it returns non-null;
  /// falls back to [idle]. A tiny declarative hook so different glyphs can feel
  /// alive in their OWN way without bespoke widgets.
  final IconEffect? Function(String icon)? idleBuilder;

  final String? semanticLabel;

  /// Cheap velocity-scaled motion blur on the morph worm (see
  /// [IconicMorph.motionBlur]). Applies only during the morph phase.
  final bool motionBlur;

  /// Fired (after frame) each time the hero comes to REST on [icon] — i.e. it has
  /// settled into idle: once after the initial appearance/intro, and again after
  /// every completed morph. This is the chaining hook [IconicMorphSequence] uses to
  /// know "the current glyph has arrived" and advance to the next icon.
  ///
  /// Fires only on an ACTUAL rest. If [icon] changes *mid-morph*, the hero chains
  /// straight into the next morph without firing for the abandoned target (it
  /// never rested) — so a listener gets exactly one signal per genuine rest, never
  /// a spurious one for a pass-through. (A sequence can't hit this anyway: it only
  /// retargets from `onSettled`, i.e. while already idle.)
  final VoidCallback? onSettled;

  /// A ONE-SHOT effect to play on the CURRENT glyph on demand (no icon change, no
  /// morph) — e.g. a lock "engages" when a passcode is set. Played when
  /// [actionController] fires `play()`, then the hero returns to idle. Null = no
  /// action. Reduced motion skips it.
  final IconEffect? actionEffect;

  /// Trigger for [actionEffect]: call `play()` to run it once on the resting glyph.
  final IconicAnimatedIconController? actionController;

  /// Override the RESTING (idle) representation of a given glyph with a bespoke
  /// widget — e.g. a self-animating lock that opens/closes by its own state. When
  /// it returns non-null for the resting icon, the hero renders it INSTEAD of the
  /// idle effect / static [IconImage] (intro + morph phases are unaffected, so a
  /// morph still lands on the plain glyph and then hands off to this widget — no
  /// seam). Null (or null return) → the normal idle/still rendering.
  final Widget? Function(String icon)? restBuilder;

  @override
  State<IconicMorphHero> createState() => _IconicMorphHeroState();
}

enum _Phase { intro, idle, morph, action }

class _IconicMorphHeroState extends State<IconicMorphHero>
    with SingleTickerProviderStateMixin {
  // Times the intro / morph phases so we know when to fall back to idle. The
  // sub-widget runs the actual animation; this just mirrors its duration. Built
  // EAGERLY (never a `late` field initializer — that would defer creation to
  // dispose if a phase never runs, crashing on the Ticker's TickerMode lookup).
  late final AnimationController _timer;

  late String _shown; // the icon currently displayed
  String? _morphFrom; // during a morph
  String? _morphTo; // during a morph
  late IconMorphPlan _morphPlan;
  bool _morphReverse = false; // play the active morph time-reversed
  _Phase _phase = _Phase.idle;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _timer = AnimationController(vsync: this)..addStatusListener(_onTimer);
    _shown = widget.icon;
    _morphPlan = widget.plan;
    widget.actionController?.addListener(_onAction);
    IconGeometry.load(widget.icon); // pre-warm → no static-fallback flash
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read + cache reduced-motion here (never from an async/status callback on a
    // possibly-deactivated element).
    _reduceMotion = IconMotion.reduced(context);
    if (!_started) {
      _started = true;
      if (widget.intro != null && !_reduceMotion) {
        _phase = _Phase.intro;
        _timer
          ..duration = widget.intro!.duration
          ..forward(from: 0);
      } else {
        // Appears straight into idle (no intro, or reduced motion) — signal the
        // initial rest so a sequence can begin advancing.
        _phase = _Phase.idle;
        _scheduleSettled();
      }
    }
  }

  @override
  void didUpdateWidget(IconicMorphHero old) {
    super.didUpdateWidget(old);
    if (old.actionController != widget.actionController) {
      old.actionController?.removeListener(_onAction);
      widget.actionController?.addListener(_onAction);
    }
    // A new target while idle/intro → morph toward it. A change mid-morph is
    // picked up when the running morph completes (see _onTimer).
    if (widget.icon != _shown && _phase != _Phase.morph) _startMorph();
  }

  /// [actionController] fired — play [actionEffect] ONCE on the resting glyph,
  /// then settle back to idle. Only from idle (never interrupting a morph/intro),
  /// and never under reduced motion.
  void _onAction() {
    if (!mounted ||
        widget.actionEffect == null ||
        widget.actionController!.stopRequested ||
        _reduceMotion ||
        _phase != _Phase.idle) {
      return;
    }
    setState(() => _phase = _Phase.action);
    _timer
      ..duration = widget.actionEffect!.duration
      ..forward(from: 0);
  }

  void _startMorph() {
    if (_reduceMotion) {
      setState(() {
        _shown = widget.icon;
        _phase = _Phase.idle;
      });
      _scheduleSettled();
      return;
    }
    IconGeometry.load(widget.icon);
    setState(() {
      _morphFrom = _shown;
      _morphTo = widget.icon;
      _morphPlan = widget.plan;
      _morphReverse = widget.reverse;
      _phase = _Phase.morph;
    });
    _timer
      ..duration = widget.plan.duration
      ..forward(from: 0);
  }

  void _onTimer(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final completedPhase = _phase;
    if (_phase == _Phase.morph) {
      _shown = _morphTo ?? _shown;
      _morphFrom = _morphTo = null;
      // Target moved again during the morph → chain straight into the next one.
      if (widget.icon != _shown) {
        _startMorph();
        return;
      }
    }
    // An ACTION completion is NOT a "genuine rest" (intro / morph arrival), so it
    // must not pulse onSettled — otherwise a IconicMorphSequence wired with an
    // actionController would spuriously advance. Honors the onSettled contract.
    _enterIdle(signal: completedPhase != _Phase.action);
  }

  /// Settle into idle and (when [signal]) fire [IconicMorphHero.onSettled] for the
  /// new rest. Action completions settle silently — see [_onTimer].
  void _enterIdle({bool signal = true}) {
    setState(() => _phase = _Phase.idle);
    if (signal) _scheduleSettled();
  }

  /// Fire [IconicMorphHero.onSettled] AFTER the current frame (so a listener may
  /// safely `setState`/advance a sequence), guarding against an unmount.
  void _scheduleSettled() {
    final cb = widget.onSettled;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
  }

  @override
  void dispose() {
    widget.actionController?.removeListener(_onAction);
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    final label = widget.semanticLabel;
    // Resolve the idle effect for the resting glyph: per-icon override first.
    final idleEffect = widget.idleBuilder?.call(_shown) ?? widget.idle;
    // A bespoke resting widget (e.g. the live lock) wins over idle/still while at
    // rest — but never during intro/morph (those still render the plain glyph).
    final restOverride =
        _phase == _Phase.idle ? widget.restBuilder?.call(_shown) : null;

    final Widget glyph = switch (_phase) {
      _Phase.intro => IconicAnimatedIcon(
          _shown,
          key: const ValueKey('hero-intro'),
          size: widget.size,
          color: color,
          effect: widget.intro!,
          semanticLabel: label,
        ),
      _Phase.morph => IconicMorph(
          // A reverse morph is the FORWARD pair played backward: hand
          // IconicMorph (target → current) so its geometry/plan match the
          // forward transition, then `reverse` rewinds it onto the target.
          _morphReverse ? _morphTo! : _morphFrom!,
          _morphReverse ? _morphFrom! : _morphTo!,
          key: ValueKey('hero-morph-$_morphFrom-$_morphTo'),
          plan: _morphPlan,
          reverse: _morphReverse,
          size: widget.size,
          color: color,
          motionBlur: widget.motionBlur,
          semanticLabel: label,
        ),
      _Phase.action => IconicAnimatedIcon(
          _shown,
          key: ValueKey('hero-action-$_shown'),
          size: widget.size,
          color: color,
          effect: widget.actionEffect!,
          semanticLabel: label,
        ),
      _Phase.idle when restOverride != null => KeyedSubtree(
          key: ValueKey('hero-rest-$_shown'),
          child: restOverride,
        ),
      _Phase.idle => (idleEffect != null && !_reduceMotion)
          ? IconicAnimatedIcon(
              _shown,
              key: ValueKey('hero-idle-$_shown'),
              size: widget.size,
              color: color,
              effect: idleEffect,
              semanticLabel: label,
            )
          : IconImage.asset(
              _shown,
              key: ValueKey('hero-still-$_shown'),
              size: widget.size,
              color: color,
              semanticLabel: label,
            ),
    };
    return glyph;
  }
}
