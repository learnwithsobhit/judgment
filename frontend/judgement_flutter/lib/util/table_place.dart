/// Current-game 2nd and 3rd. 1st stays the crown and leader line.
library;

import 'package:flutter/material.dart';

import '../models/protocol.dart';

/// Silver / bronze rail on the name chip. No extra height, no numeral.
class TablePlaceRail extends StatelessWidget {
  const TablePlaceRail({super.key, required this.place});

  /// Only `2` or `3`.
  final int place;

  static const silver = Color(0xFFC0C0C0);
  static const bronze = Color(0xFFCD7F32);

  Color get color => place == 2 ? silver : bronze;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: place == 2 ? '2nd' : '3rd',
      child: ColoredBox(color: color, child: const SizedBox(width: 3)),
    );
  }
}

class TablePlace {
  /// `2` or `3` for that seat. 1st, ties for the lead, and everyone else
  /// are absent. Empty until the first round has a result, same as the crown.
  static Map<String, int> marks(PlayerGameView view) {
    return marksFor(
      historyStarted: view.roundHistory.isNotEmpty,
      scores: view.scores,
    );
  }

  static Map<String, int> marksFor({
    required bool historyStarted,
    required List<PlayerScore> scores,
  }) {
    if (!historyStarted || scores.isEmpty) return const {};
    var maxScore = scores.first.totalScore;
    for (final row in scores) {
      if (row.totalScore > maxScore) maxScore = row.totalScore;
    }
    final below = <int>{};
    for (final row in scores) {
      if (row.totalScore < maxScore) below.add(row.totalScore);
    }
    if (below.isEmpty) return const {};
    final distinct = below.toList()..sort((a, b) => b.compareTo(a));
    final secondScore = distinct.first;
    var secondCount = 0;
    for (final row in scores) {
      if (row.totalScore == secondScore) secondCount++;
    }
    final thirdScore = secondCount == 1 && distinct.length > 1
        ? distinct[1]
        : null;
    final out = <String, int>{};
    for (final row in scores) {
      if (row.totalScore == secondScore) {
        out[row.playerId] = 2;
      } else if (thirdScore != null && row.totalScore == thirdScore) {
        out[row.playerId] = 3;
      }
    }
    return out;
  }
}
