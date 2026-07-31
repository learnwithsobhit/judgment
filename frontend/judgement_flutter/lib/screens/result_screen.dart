import 'package:flutter/material.dart';

import '../app/app.dart';
import '../state/game_controller.dart';
import '../widgets/coaching_panel.dart';

/// Final standings, including the locked tie-break columns
/// (score, then exact-bid rounds, then fewest tricks missed — PLAN.md §5.7).
class ResultScreen extends StatelessWidget {
  final GameController controller;

  const ResultScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ranking = controller.view?.finalRanking ?? [];
    final winners = ranking.where((r) => r.rank == 1).toList();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events, size: 64, color: goldAccent),
                const SizedBox(height: 8),
                Text(
                  winners.length == 1
                      ? '${controller.nicknameOf(winners.first.playerId)} wins!'
                      : 'Shared victory: ${winners.map((w) => controller.nicknameOf(w.playerId)).join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),
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
                          DataColumn(label: Text('Score'), numeric: true),
                          DataColumn(
                            label: Tooltip(
                              message: 'Rounds where the bid was hit exactly (first tie-break)',
                              child: Text('Exact rounds'),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Tooltip(
                              message: 'Total tricks off from the bid (second tie-break)',
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
                                DataCell(Text(
                                  controller.nicknameOf(ranked.playerId) +
                                      (ranked.playerId == controller.myPlayerId
                                          ? ' (you)'
                                          : ''),
                                  style: TextStyle(
                                    fontWeight: ranked.rank == 1
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                )),
                                DataCell(Text('${ranked.totalScore}')),
                                DataCell(Text('${ranked.exactBidRounds}')),
                                DataCell(Text('${ranked.totalTricksMissed}')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
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
