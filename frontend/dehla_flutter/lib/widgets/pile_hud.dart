import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../theme/dehla_theme.dart';
import 'playing_card.dart';

/// Centre pile + one-away — designed to sit on the felt oval.
class PileHud extends StatelessWidget {
  const PileHud({
    super.key,
    required this.pileCount,
    this.lastWinnerName,
    this.oneAwayName,
    this.trump,
    required this.tricksPlayed,
  });

  final int pileCount;
  final String? lastWinnerName;
  final String? oneAwayName;
  final String? trump;
  final int tricksPlayed;

  @override
  Widget build(BuildContext context) {
    final oneAway = oneAwayName != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: oneAway ? goldAccent : Colors.white24,
          width: oneAway ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < pileCount.clamp(0, 4); i++)
                  Positioned(
                    left: i * 3.0,
                    top: i * 1.5,
                    child: const CardBack(width: 28),
                  ),
                if (pileCount == 0)
                  const Center(
                    child: Text('—', style: TextStyle(color: Colors.white38)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pile · $pileCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                lastWinnerName == null
                    ? 'No prior trick winner'
                    : 'Last: $lastWinnerName',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (oneAway)
                Text(
                  '$oneAwayName one win from capture!',
                  style: const TextStyle(
                    color: goldAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              Text(
                trump == null
                    ? 'Trump — · $tricksPlayed/13'
                    : 'Trump ${suitSymbols[trump] ?? trump} · $tricksPlayed/13',
                style: TextStyle(color: suitColor(trump), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
