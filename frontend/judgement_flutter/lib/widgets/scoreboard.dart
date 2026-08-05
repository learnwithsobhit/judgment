import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/score_reveal.dart';
import 'player_avatar.dart';
import 'round_score_matrix.dart';

/// Scoreboard: current bid/won, round scores, and cumulative totals after
/// halftime (⌈M/2⌉) or once the ≤3-card phase begins.
class Scoreboard extends StatelessWidget {
  final GameController controller;

  const Scoreboard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    if (view == null) return const SizedBox.shrink();

    final bidsByPlayer = {for (final b in view.bids) b.playerId: b.bid};
    final reveal = ScoreReveal.fromView(view);
    final showTotals = reveal.showTotals;
    final history = view.roundHistory;
    final leaderId = view.leader?.playerId;

    final players = <_PlayerRow>[
      _PlayerRow(
        playerId: controller.myPlayerId,
        seat: view.ownSeat,
        name: '${controller.myNickname} (you)',
        avatarId: view.ownAvatarId,
        bid: bidsByPlayer[controller.myPlayerId] ?? view.ownBid,
        tricksWon: view.ownTricksWon,
        total: _totalFor(view, controller.myPlayerId),
      ),
      for (final o in view.opponents)
        _PlayerRow(
          playerId: o.playerId,
          seat: o.seat,
          name: o.nickname,
          avatarId: o.avatarId,
          bid: o.bid,
          tricksWon: o.tricksWon,
          total: _totalFor(view, o.playerId),
        ),
    ]..sort((a, b) => a.seat.compareTo(b.seat));

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

        // Current round: bid / tricks won only.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            'This round',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Expanded(child: Text('Player', style: _headerStyle)),
              _numCell(const Text('Bid', style: _headerStyle)),
              _numCell(const Text('Won', style: _headerStyle)),
            ],
          ),
        ),
        for (final row in players)
          _currentRoundRow(
            view: view,
            row: row,
            isLeader: leaderId == row.playerId,
          ),

        const Divider(height: 16),

        // Completed rounds as rows; players as columns (≤8).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(
            'Round scores',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Text(
              'Scores appear here after each round ends.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: RoundScoreMatrix(
              columns: [
                for (final row in players)
                  RoundScoreColumn(
                    playerId: row.playerId,
                    displayName: row.name
                        .replaceAll(RegExp(r'\s*\(you\)\s*'), '')
                        .trim(),
                    avatarId: row.avatarId,
                    highlightHeader: leaderId == row.playerId,
                    total: row.total,
                  ),
              ],
              history: history,
              showTotals: showTotals,
              emphasizePlayerId: view.currentTurn,
              footerHint: 'Exact bid = 10 + bid · miss = 0',
            ),
          ),
          if (!showTotals)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Text(
                'Totals unlock after round ${reveal.unlockAfterRound} of ${reveal.totalRounds}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _currentRoundRow({
    required PlayerGameView view,
    required _PlayerRow row,
    required bool isLeader,
  }) {
    return Container(
      color: view.currentTurn == row.playerId
          ? goldAccent.withValues(alpha: 0.12)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _playerLabel(row, isLeader, view.round?.dealer)),
          _numCell(Text('${row.bid ?? '—'}')),
          _numCell(Text('${row.tricksWon}')),
        ],
      ),
    );
  }

  static Widget _playerLabel(_PlayerRow row, bool isLeader, String? dealerId) {
    return Row(
      children: [
        PlayerAvatar(
          avatarId: row.avatarId,
          nickname: row.name,
          radius: 12,
          highlight: isLeader,
        ),
        const SizedBox(width: 6),
        if (dealerId == row.playerId)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Tooltip(
              message: 'Dealer',
              child: CircleAvatar(
                radius: 9,
                backgroundColor: goldAccent,
                child: Text(
                  'D',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        if (isLeader)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Text('👑', style: TextStyle(fontSize: 12)),
          ),
        Flexible(
          child: Text(row.name, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  static int? _totalFor(PlayerGameView view, String playerId) => view.scores
      .where((s) => s.playerId == playerId)
      .map((s) => s.totalScore)
      .firstOrNull;

  static Widget _numCell(Widget child) =>
      SizedBox(width: 44, child: Center(child: child));

  static const _headerStyle =
      TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600);
}

class _PlayerRow {
  final String playerId;
  final int seat;
  final String name;
  final String? avatarId;
  final int? bid;
  final int tricksWon;
  final int? total;

  _PlayerRow({
    required this.playerId,
    required this.seat,
    required this.name,
    required this.avatarId,
    required this.bid,
    required this.tricksWon,
    required this.total,
  });
}
