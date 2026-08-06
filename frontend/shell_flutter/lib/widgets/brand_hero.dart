import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/table_games_theme.dart';
import '../ux/copy.dart';

/// Full-bleed club foyer hero — brand first, no game cards.
class BrandHero extends StatelessWidget {
  final VoidCallback? onBrowseTables;

  const BrandHero({super.key, this.onBrowseTables});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return Semantics(
      header: true,
      label: TableGamesCopy.brand,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 20 : 48,
          compact ? 20 : 40,
          compact ? 20 : 48,
          compact ? 20 : 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '♠  ♥  ♦  ♣',
              style: TextStyle(
                color: goldAccent.withValues(alpha: 0.85),
                fontSize: compact ? 18 : 22,
                letterSpacing: 10,
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(
              TableGamesCopy.brand,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: goldAccent,
                fontSize: compact ? 42 : 64,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(
              TableGamesCopy.tagline,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceSans3(
                color: suitLight.withValues(alpha: 0.9),
                fontSize: compact ? 16 : 18,
                height: 1.35,
              ),
            ),
            if (onBrowseTables != null) ...[
              SizedBox(height: compact ? 20 : 28),
              OutlinedButton(
                onPressed: onBrowseTables,
                child: const Text(TableGamesCopy.browseTables),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
