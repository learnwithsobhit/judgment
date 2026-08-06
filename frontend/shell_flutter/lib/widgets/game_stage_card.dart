import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/game_catalog.dart';
import '../theme/table_games_theme.dart';

class GameStageCard extends StatefulWidget {
  final GameEntry game;
  final VoidCallback? onPlay;
  final VoidCallback? onNotify;
  /// Overrides the live CTA label (e.g. "Join room" for pending invites).
  final String? playLabel;

  const GameStageCard({
    super.key,
    required this.game,
    this.onPlay,
    this.onNotify,
    this.playLabel,
  });

  @override
  State<GameStageCard> createState() => _GameStageCardState();
}

class _GameStageCardState extends State<GameStageCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final live = game.isLive;
    final accent = Color(game.accentArgb);
    final scale = _hovered ? 1.02 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Semantics(
          button: true,
          label: live
              ? '${game.name}. ${game.tagline}. Play'
              : '${game.name}. Coming soon',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered
                    ? goldAccent.withValues(alpha: 0.85)
                    : woodBorder.withValues(alpha: live ? 0.9 : 0.45),
                width: 2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: live
                    ? [
                        feltGreenMid.withValues(alpha: 0.95),
                        feltGreenDark,
                      ]
                    : [
                        feltGreenDark.withValues(alpha: 0.7),
                        const Color(0xFF0A1F0C),
                      ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        game.suitMark,
                        style: TextStyle(
                          color: accent.withValues(alpha: live ? 1 : 0.45),
                          fontSize: 28,
                        ),
                      ),
                      const Spacer(),
                      if (!live)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: suitLight.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            'Coming soon',
                            style: GoogleFonts.sourceSans3(
                              color: suitLight.withValues(alpha: 0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: goldAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: goldAccent.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Live',
                            style: GoogleFonts.sourceSans3(
                              color: goldAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    game.name,
                    style: GoogleFonts.playfairDisplay(
                      color:
                          live ? goldAccent : suitLight.withValues(alpha: 0.55),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    game.tagline,
                    style: GoogleFonts.sourceSans3(
                      color: suitLight.withValues(alpha: live ? 0.88 : 0.45),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    game.playerRange,
                    style: GoogleFonts.sourceSans3(
                      color: suitLight.withValues(alpha: live ? 0.65 : 0.35),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 14),
                  if (live)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.onPlay,
                        child: Text(widget.playLabel ?? 'Play'),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: widget.onNotify,
                        child: const Text('Notify me'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
