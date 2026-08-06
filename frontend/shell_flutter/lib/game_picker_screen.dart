import 'package:dehla_flutter/dehla_flutter.dart';
import 'package:flutter/material.dart';

/// Brand-first game home — Judgement | Dehla Pakad.
class GamePickerScreen extends StatelessWidget {
  const GamePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: feltGreenDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '♠ ♥ ♦ ♣',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: goldAccent,
                  fontSize: 20,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Table games',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: goldAccent,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a game. Each table runs on its own server.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 36),
              _GameCard(
                title: 'Judgement',
                subtitle: 'Bids, tricks, and trump — Oh Hell.',
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Judgement'),
                      content: const Text(
                        'Judgement stays on the existing judgement_flutter '
                        'app so there is no regression.\n\n'
                        'Run frontend/judgement_flutter for Judgement play.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _GameCard(
                title: 'Dehla Pakad',
                subtitle: 'Protect the tens. Control the pile. Win the Kot.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DehlaHomeScreen(),
                    ),
                  );
                },
              ),
              const Spacer(),
              Text(
                'Version ${const String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: feltGreen,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: goldAccent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: goldAccent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
