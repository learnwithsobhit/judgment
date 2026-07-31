import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/game_controller.dart';

/// Overlay that animates ephemeral table reactions toward the felt center.
class EmojiBlastOverlay extends StatelessWidget {
  final GameController controller;

  const EmojiBlastOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bursts = controller.activeBursts;
    if (bursts.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        children: [
          for (final burst in bursts) _BurstParticles(burst: burst),
        ],
      ),
    );
  }
}

class _BurstParticles extends StatefulWidget {
  final EmoteBurst burst;

  const _BurstParticles({required this.burst});

  @override
  State<_BurstParticles> createState() => _BurstParticlesState();
}

class _BurstParticlesState extends State<_BurstParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.burst.ttlMs),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emojis = widget.burst.emojis.isEmpty ? const ['✨'] : widget.burst.emojis;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_ctrl.value);
        final opacity = (1 - _ctrl.value).clamp(0.0, 1.0);
        return LayoutBuilder(
          builder: (context, constraints) {
            final cx = constraints.maxWidth / 2;
            final cy = constraints.maxHeight / 2;
            return Stack(
              children: [
                for (var i = 0; i < emojis.length; i++)
                  Positioned(
                    left: cx +
                        math.cos(i * 2.1) * 40 * (1 - t) -
                        14 +
                        math.sin(i + t * 6) * 18,
                    top: cy +
                        math.sin(i * 1.7) * 28 * (1 - t) -
                        14 -
                        t * 36,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: 0.8 + t * 0.7,
                        child: Text(emojis[i], style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
