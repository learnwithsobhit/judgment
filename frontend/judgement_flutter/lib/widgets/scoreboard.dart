import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/score_reveal.dart';
import 'player_avatar.dart';

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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: _RoundScoreMatrix(
              players: players,
              history: history,
              showTotals: showTotals,
              leaderId: leaderId,
              currentTurn: view.currentTurn,
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

class _RoundScoreMatrix extends StatelessWidget {
  final List<_PlayerRow> players;
  final List<RoundScoreView> history;
  final bool showTotals;
  final String? leaderId;
  final String? currentTurn;

  const _RoundScoreMatrix({
    required this.players,
    required this.history,
    required this.showTotals,
    required this.leaderId,
    required this.currentTurn,
  });

  @override
  Widget build(BuildContext context) {
    // Rounds as rows, players as columns (≤8 players, many rounds).
    // Columns size to full nicknames (horizontal scroll if needed).
    const roundW = 44.0;
    final names = [
      for (final row in players) _displayName(row.name),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: const {0: FixedColumnWidth(roundW)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Rnd', style: Scoreboard._headerStyle),
                ),
                for (var i = 0; i < players.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      names[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: leaderId == players[i].playerId
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
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'R${r.roundIndex + 1}',
                      style: Scoreboard._headerStyle,
                    ),
                  ),
                  for (final row in players)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _scoreFor(r, row.playerId),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: currentTurn == row.playerId
                              ? goldAccent
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            if (showTotals)
              TableRow(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Tot',
                      style: TextStyle(
                        fontSize: 12,
                        color: goldAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final row in players)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '${row.total ?? 0}',
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
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Exact bid = 10 + bid · miss = 0',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }

  /// Full nickname for column headers (drop the "(you)" suffix to keep columns tidy).
  String _displayName(String name) {
    return name.replaceAll(RegExp(r'\s*\(you\)\s*'), '').trim();
  }

  String _scoreFor(RoundScoreView round, String playerId) {
    for (final e in round.entries) {
      if (e.playerId == playerId) {
        return '${e.score}';
      }
    }
    return '—';
  }
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
