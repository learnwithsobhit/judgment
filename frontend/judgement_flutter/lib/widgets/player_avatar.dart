import 'package:flutter/material.dart';

import '../util/avatar_pack.dart';

/// Built-in pack avatar with optional cheer / flash scale bounce.
class PlayerAvatar extends StatefulWidget {
  final String? avatarId;
  final String nickname;
  final double radius;
  final bool highlight;
  final bool muted;
  final String? flashMood;
  final VoidCallback? onLongPress;

  const PlayerAvatar({
    super.key,
    required this.avatarId,
    required this.nickname,
    this.radius = 20,
    this.highlight = false,
    this.muted = false,
    this.flashMood,
    this.onLongPress,
  });

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// Do not wrap [TweenSequence] in overshooting curves (e.g. easeOutBack) —
  /// that feeds t > 1 into [TweenSequence.transform] and asserts.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.28)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.28, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 60,
    ),
  ]).animate(_ctrl);

  String? _lastMood;

  @override
  void didUpdateWidget(covariant PlayerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashMood != null &&
        widget.flashMood != _lastMood &&
        mounted) {
      _lastMood = widget.flashMood;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.nickname.isNotEmpty ? widget.nickname[0] : '?';
    final glyph = avatarGlyph(widget.avatarId, fallbackLetter: letter);
    final child = ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.highlight
                ? const Color(0xFFD4AF37)
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: CircleAvatar(
          radius: widget.radius,
          backgroundColor: widget.muted
              ? Colors.grey.shade700
              : const Color(0xFF37474F),
          child: widget.muted
              ? Icon(Icons.wifi_off,
                  size: widget.radius * 0.9, color: Colors.white54)
              : Text(glyph, style: TextStyle(fontSize: widget.radius * 0.95)),
        ),
      ),
    );
    if (widget.onLongPress == null) return child;
    return GestureDetector(onLongPress: widget.onLongPress, child: child);
  }
}
