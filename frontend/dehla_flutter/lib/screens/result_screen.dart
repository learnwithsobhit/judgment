import 'package:flutter/material.dart';

import '../theme/dehla_theme.dart';

/// Full-screen match result (optional). Prefer in-table rematch chrome so the
/// WebSocket stays live — use [onRematch] when still connected.
class DehlaResultScreen extends StatelessWidget {
  const DehlaResultScreen({
    super.key,
    required this.winnerTeam,
    required this.kotsA,
    required this.kotsB,
    this.onRematch,
    this.canRematch = false,
  });

  final String winnerTeam;
  final int kotsA;
  final int kotsB;
  final VoidCallback? onRematch;
  final bool canRematch;

  @override
  Widget build(BuildContext context) {
    final winnerRing = teamRingFor(winnerTeam) ?? goldAccent;
    final side = teamSideLabel(winnerTeam);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [feltGreen, feltGreenDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: winnerRing, width: 4),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        size: 72,
                        color: goldAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$side side wins!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: winnerRing,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ScoreSide(color: teamRingWarm, kots: kotsA),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '–',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _ScoreSide(color: teamRingCool, kots: kotsB),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Final Kots',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (canRematch && onRematch != null) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: onRematch,
                          child: const Text('Rematch'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                        child: const Text('Back to home'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreSide extends StatelessWidget {
  const _ScoreSide({required this.color, required this.kots});

  final Color color;
  final int kots;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$kots',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
