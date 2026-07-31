import 'package:flutter/material.dart';

import '../app/app.dart';
import '../state/game_controller.dart';

/// Live scoreboard: bids, tricks won, and running totals for every seat.
class Scoreboard extends StatelessWidget {
  final GameController controller;

  const Scoreboard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    if (view == null) return const SizedBox.shrink();

    final bidsByPlayer = {for (final b in view.bids) b.playerId: b.bid};
    final totals = {for (final s in view.scores) s.playerId: s.totalScore};

    // All players in seat order: self plus opponents (4-8 seats, possibly
    // non-contiguous — ADR 0003).
    final rows = <(int, _ScoreRow)>[
      (
        view.ownSeat,
        _ScoreRow(
          playerId: controller.myPlayerId,
          name: '${controller.myNickname} (you)',
          bid: bidsByPlayer[controller.myPlayerId] ?? view.ownBid,
          tricksWon: view.ownTricksWon,
          total: totals[controller.myPlayerId] ?? 0,
        ),
      ),
      for (final o in view.opponents)
        (
          o.seat,
          _ScoreRow(
            playerId: o.playerId,
            name: o.nickname,
            bid: o.bid,
            tricksWon: o.tricksWon,
            total: totals[o.playerId] ?? 0,
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final round = view.round;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            round == null
                ? 'Scoreboard'
                : 'Round ${round.roundIndex + 1} of ${round.totalRounds} · ${round.cardsPerPlayer} cards',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Expanded(child: Text('Player', style: _headerStyle)),
              _numCell(const Text('Bid', style: _headerStyle)),
              _numCell(const Text('Won', style: _headerStyle)),
              _numCell(const Text('Total', style: _headerStyle)),
            ],
          ),
        ),
        for (final (_, row) in rows)
          Container(
            color: view.currentTurn == row.playerId
                ? goldAccent.withValues(alpha: 0.12)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (round?.dealer == row.playerId)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: 'Dealer',
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: goldAccent,
                              child: Text('D',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(row.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                _numCell(Text('${row.bid ?? '—'}')),
                _numCell(Text('${row.tricksWon}')),
                _numCell(Text(
                  '${row.total}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _numCell(Widget child) =>
      SizedBox(width: 44, child: Center(child: child));

  static const _headerStyle =
      TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600);
}

class _ScoreRow {
  final String playerId;
  final String name;
  final int? bid;
  final int tricksWon;
  final int total;

  _ScoreRow({
    required this.playerId,
    required this.name,
    required this.bid,
    required this.tricksWon,
    required this.total,
  });
}
