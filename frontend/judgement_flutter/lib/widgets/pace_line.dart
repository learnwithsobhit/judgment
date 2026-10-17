import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../util/seat_label.dart';

/// Shared fastest and slowest seats, with the time each one has used.
class PaceLine extends StatelessWidget {
  final GameController controller;
  final TextAlign textAlign;

  const PaceLine({
    super.key,
    required this.controller,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final fastest = controller.fastestPlayer;
    final slowest = controller.slowestPlayer;
    if (fastest == null || slowest == null) return const SizedBox.shrink();
    final fastName = seatLabel(controller.nicknameOf(fastest.playerId));
    final slowName = seatLabel(controller.nicknameOf(slowest.playerId));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Fastest $fastName ${formatPace(fastest.time)}'
        ' · Slowest $slowName ${formatPace(slowest.time)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.75),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

String formatPace(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
