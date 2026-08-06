import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/table_games_theme.dart';
import '../ux/copy.dart';

/// Resume / pending-invite strip.
class ContinueRail extends StatelessWidget {
  final String? roomCode;
  final String? title;
  final String? subtitle;
  final VoidCallback onResume;

  const ContinueRail({
    super.key,
    this.roomCode,
    this.title,
    this.subtitle,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final heading = title ?? TableGamesCopy.continueJudgement;
    final sub = subtitle ??
        '${TableGamesCopy.continueHint}${roomCode != null ? ' · $roomCode' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Material(
        color: feltGreen.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: goldAccent.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onResume,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline,
                    color: goldAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: GoogleFonts.sourceSans3(
                          color: goldAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        sub,
                        style: GoogleFonts.sourceSans3(
                          color: suitLight.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward,
                    color: goldAccent.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
