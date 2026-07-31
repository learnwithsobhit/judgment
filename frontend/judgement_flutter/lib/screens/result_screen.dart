import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../widgets/coaching_panel.dart';
import '../widgets/player_avatar.dart';

/// Final standings with round-by-round scores for verification,
/// plus locked tie-break columns (PLAN.md §5.7).
class ResultScreen extends StatelessWidget {
  final GameController controller;

  const ResultScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    final ranking = view?.finalRanking ?? [];
    final history = view?.roundHistory ?? const <RoundScoreView>[];
    final winners = ranking.where((r) => r.rank == 1).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events, size: 64, color: goldAccent),
                const SizedBox(height: 8),
                Text(
                  winners.isEmpty
                      ? 'Game over'
                      : winners.length == 1
                          ? '${controller.nicknameOf(winners.first.playerId)} wins!'
                          : 'Shared victory: ${winners.map((w) => controller.nicknameOf(w.playerId)).join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Final tally',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('Player')),
                          DataColumn(label: Text('Total'), numeric: true),
                          DataColumn(
                            label: Tooltip(
                              message:
                                  'Rounds where the bid was hit exactly (first tie-break)',
                              child: Text('Exact rounds'),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Tooltip(
                              message:
                                  'Total tricks off from the bid (second tie-break)',
                              child: Text('Tricks missed'),
                            ),
                            numeric: true,
                          ),
                        ],
                        rows: [
                          for (final ranked in ranking)
                            DataRow(
                              color: ranked.rank == 1
                                  ? WidgetStatePropertyAll(
                                      goldAccent.withValues(alpha: 0.15))
                                  : null,
                              cells: [
                                DataCell(Text('${ranked.rank}')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PlayerAvatar(
                                        avatarId: controller
                                            .avatarOf(ranked.playerId),
                                        nickname: controller
                                            .nicknameOf(ranked.playerId),
                                        radius: 12,
                                        highlight: ranked.rank == 1,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        controller.nicknameOf(ranked.playerId) +
                                            (ranked.playerId ==
                                                    controller.myPlayerId
                                                ? ' (you)'
                                                : ''),
                                        style: TextStyle(
                                          fontWeight: ranked.rank == 1
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(
                                  '${ranked.totalScore}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                )),
                                DataCell(Text('${ranked.exactBidRounds}')),
                                DataCell(Text('${ranked.totalTricksMissed}')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (history.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Round-by-round scores',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Check each round against the total (exact bid = 10 + bid · miss = 0)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: _RoundVerifyMatrix(
                        controller: controller,
                        ranking: ranking,
                        history: history,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your coach',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CoachingPanel(
                  api: controller.api,
                  gameId: controller.gameId,
                  playerId: controller.myPlayerId,
                  nicknameOf: controller.nicknameOf,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home),
                  label: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundVerifyMatrix extends StatelessWidget {
  final GameController controller;
  final List<RankedPlayer> ranking;
  final List<RoundScoreView> history;

  const _RoundVerifyMatrix({
    required this.controller,
    required this.ranking,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    // Rounds as rows, players as columns (≤8 players, many rounds).
    // Columns size to full nicknames (horizontal scroll if needed).
    const roundW = 52.0;

    // Player order matches final ranking for easy cross-check.
    final playerIds = ranking.map((r) => r.playerId).toList();
    if (playerIds.isEmpty) {
      final view = controller.view!;
      playerIds.add(controller.myPlayerId);
      playerIds.addAll(view.opponents.map((o) => o.playerId));
    }

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      columnWidths: const {0: FixedColumnWidth(roundW)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Round',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final playerId in playerIds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  controller.nicknameOf(playerId),
                  style: TextStyle(
                    fontSize: 12,
                    color: playerId == controller.myPlayerId
                        ? goldAccent
                        : Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        for (final r in history)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  'R${r.roundIndex + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final playerId in playerIds)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Tooltip(
                    message: _roundTooltip(r, playerId),
                    child: Text(
                      _score(r, playerId),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Total',
                style: TextStyle(
                  fontSize: 12,
                  color: goldAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final playerId in playerIds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  '${_columnSum(playerId)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: goldAccent,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _score(RoundScoreView round, String playerId) {
    for (final e in round.entries) {
      if (e.playerId == playerId) return '${e.score}';
    }
    return '—';
  }

  int _columnSum(String playerId) {
    var sum = 0;
    for (final r in history) {
      for (final e in r.entries) {
        if (e.playerId == playerId) sum += e.score;
      }
    }
    return sum;
  }

  String _roundTooltip(RoundScoreView round, String playerId) {
    for (final e in round.entries) {
      if (e.playerId == playerId) {
        return '${controller.nicknameOf(playerId)} · R${round.roundIndex + 1}: '
            'bid ${e.bid} → won ${e.tricksWon} → ${e.score} pts';
      }
    }
    return 'No score';
  }
}
