import 'dart:async';

import 'package:flutter/widgets.dart';

import '../icon_animation_profile.dart';
import '../icon_effect.dart';
import 'morph_hero.dart';
import 'morph_plan.dart';

/// A **chain of morphs** — one persistent glyph that flows through a *string* of
/// icons in order (`A → B → C → …`), morphing from each to the next, resting
/// briefly on each. The scalable answer to "morph 2, 3, or more icons": pass the
/// list, get a single living glyph that walks it.
///
/// ```dart
/// IconicMorphSequence([MorphIcons.user, MorphIcons.face, MorphIcons.lock])
/// ```
///
/// Each step's morph [plan][IconMorphPlan] and idle effect resolve from
/// [IconAnimations] by default (so registering an icon's profile once is all
/// it takes), or override per call with [planFor] / [idleBuilder]. It reuses the
/// whole [IconicMorphHero] state machine (one element, no remounts → no flicker) and
/// advances on the hero's `onSettled` signal, so a step always fully arrives
/// before the next launches. [loop] cycles back to the start; otherwise it rests
/// on the final icon. Reduced motion collapses each morph to an instant swap, so
/// it degrades to a calm slideshow rather than freezing.
class IconicMorphSequence extends StatefulWidget {
  const IconicMorphSequence(
    this.icons, {
    super.key,
    this.size = 24,
    this.color,
    this.planFor,
    this.idleBuilder,
    this.intro,
    this.dwell = const Duration(milliseconds: 900),
    this.loop = true,
    this.autoplay = true,
    this.motionBlur = false,
    this.semanticLabel,
  });

  /// The ordered icons to morph through. 1 entry = a static glyph; 2+ chains.
  final List<String> icons;

  final double size;
  final Color? color;

  /// Plan used to morph INTO a given icon. Null → [IconAnimations.planFor].
  final IconMorphPlan Function(String icon)? planFor;

  /// Per-icon idle override. Null → [IconAnimations.idleFor].
  final IconEffect? Function(String icon)? idleBuilder;

  /// Intro effect for the FIRST icon's appearance. Null → the first icon's
  /// registered intro, else none.
  final IconEffect? intro;

  /// How long the glyph rests on each icon before morphing to the next.
  final Duration dwell;

  /// Cycle back to the first icon after the last (else rest on the last).
  final bool loop;

  /// Advance automatically. When false the glyph holds on the first icon (a
  /// controller-driven mode can be layered on later).
  final bool autoplay;

  /// Velocity motion blur on each morph (see [IconicMorphHero.motionBlur]).
  final bool motionBlur;

  final String? semanticLabel;

  @override
  State<IconicMorphSequence> createState() => _IconicMorphSequenceState();
}

class _IconicMorphSequenceState extends State<IconicMorphSequence> {
  int _index = 0;
  Timer? _dwell;

  @override
  void didUpdateWidget(IconicMorphSequence old) {
    super.didUpdateWidget(old);
    // The list changed under us — keep the index in range.
    if (_index >= widget.icons.length) {
      _dwell?.cancel();
      _index = widget.icons.isEmpty ? 0 : widget.icons.length - 1;
    }
  }

  /// The hero has come to rest on the current icon → schedule the next morph.
  void _onSettled() {
    if (!widget.autoplay || widget.icons.length < 2) return;
    final next = _nextIndex();
    if (next == _index) return; // end of a non-looping chain
    _dwell?.cancel();
    _dwell = Timer(widget.dwell, () {
      // `next` was captured when the timer was scheduled; if the list shrank
      // before it fired, guard the index so build()'s `icons[_index]` can't
      // RangeError (didUpdateWidget only clamps the field, not this capture).
      if (mounted && next < widget.icons.length) setState(() => _index = next);
    });
  }

  int _nextIndex() {
    if (_index + 1 < widget.icons.length) return _index + 1;
    return widget.loop ? 0 : _index;
  }

  IconMorphPlan _planFor(String icon) =>
      (widget.planFor ?? IconAnimations.planFor)(icon);

  IconEffect? _idleFor(String icon) =>
      (widget.idleBuilder ?? IconAnimations.idleFor)(icon);

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.icons.isEmpty) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final icon = widget.icons[_index];
    return IconicMorphHero(
      icon,
      size: widget.size,
      color: widget.color,
      plan: _planFor(icon),
      intro: _index == 0 ? (widget.intro ?? IconAnimations.introFor(icon)) : null,
      idleBuilder: _idleFor,
      motionBlur: widget.motionBlur,
      semanticLabel: widget.semanticLabel,
      onSettled: _onSettled,
    );
  }
}
