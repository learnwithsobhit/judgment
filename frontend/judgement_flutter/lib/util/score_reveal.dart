/// When cumulative TOTAL scores become visible on the scoreboard.
library;

import '../models/protocol.dart';

/// Halftime unlock: after round ⌈M/2⌉, or once the ≤3-card phase begins.
class ScoreReveal {
  final bool showTotals;
  final int totalRounds;
  final int completedRounds;
  final int unlockAfterRound;

  const ScoreReveal({
    required this.showTotals,
    required this.totalRounds,
    required this.completedRounds,
    required this.unlockAfterRound,
  });

  /// 1-based round number when totals unlock (⌈M/2⌉).
  static int unlockAfterRoundFor(int totalRounds) {
    if (totalRounds <= 0) return 1;
    return (totalRounds + 1) ~/ 2;
  }

  static ScoreReveal fromView(PlayerGameView view) {
    final completed = view.roundHistory.length;
    final round = view.round;
    final totalRounds = round?.totalRounds ??
        (completed > 0 ? completed : 1);
    final cards = round?.cardsPerPlayer ?? 99;
    final unlockAfter = unlockAfterRoundFor(totalRounds);

    final show = view.isFinished ||
        completed >= unlockAfter ||
        (completed >= 1 && cards <= 3);

    return ScoreReveal(
      showTotals: show,
      totalRounds: totalRounds,
      completedRounds: completed,
      unlockAfterRound: unlockAfter,
    );
  }

  /// Pure helper for unit tests (no view).
  static bool shouldShowTotals({
    required bool isFinished,
    required int totalRounds,
    required int completedRounds,
    required int cardsPerPlayer,
  }) {
    if (isFinished) return true;
    final unlockAfter = unlockAfterRoundFor(totalRounds);
    if (completedRounds >= unlockAfter) return true;
    if (completedRounds >= 1 && cardsPerPlayer <= 3) return true;
    return false;
  }
}
