/// Ranked players. The rules stay folded so the names can fill the phone.
library;

import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import 'player_avatar.dart';
import 'profile_sheet.dart';

typedef LeaderboardLoad = Future<LeaderboardReport> Function();

LeaderboardLoad leaderboardLoad = () => ApiClient().getLeaderboard();

class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key});

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet> {
  late final Future<LeaderboardReport> _load = leaderboardLoad();
  late final Future<MeStats?> _place = _loadPlace();

  Future<MeStats?> _loadPlace() async {
    if (!AccountSession.instance.isSignedIn) return null;
    try {
      return await profileStatsLoad();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Top players',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Most wins, then win rate, then bid rate',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<LeaderboardReport>(
                      future: _load,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Couldn\'t load the board. You can still play.',
                              ),
                            ),
                          );
                        }
                        final report =
                            snapshot.data ??
                            const LeaderboardReport(players: []);
                        final rows = report.players;
                        return Column(
                          children: [
                            _PulseBlock(pulse: report.pulse, place: _place),
                            if (rows.isEmpty)
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Text('No ranked games yet.'),
                                  ),
                                ),
                              )
                            else
                              Expanded(child: _BoardTable(rows: rows)),
                          ],
                        );
                      },
                    ),
                  ),
                  const _BoardKey(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PulseBlock extends StatelessWidget {
  const _PulseBlock({required this.pulse, required this.place});

  final LeaderboardPulse? pulse;
  final Future<MeStats?> place;

  @override
  Widget build(BuildContext context) {
    final figures =
        pulse ??
        const LeaderboardPulse(
          gamesToday: 0,
          gamesWeek: 0,
          gamesAll: 0,
          playersWeek: 0,
        );
    final quiet = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    final leader = figures.weekLeaderName;
    final wins = figures.weekLeaderWins;
    final lastLeader = figures.lastWeekLeaderName;
    final lastWins = figures.lastWeekLeaderWins;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PulseFigure(label: 'Today', value: figures.gamesToday),
            _PulseFigure(label: 'Week', value: figures.gamesWeek),
            _PulseFigure(label: 'Last week', value: figures.gamesLastWeek),
            _PulseFigure(label: 'All', value: figures.gamesAll),
          ],
        ),
        const SizedBox(height: 6),
        Text(_pulseCaption(figures), style: quiet),
        if (leader != null && wins > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$leader leads this week with $wins ${wins == 1 ? 'win' : 'wins'}.',
            style: quiet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (lastLeader != null && lastWins > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$lastLeader led last week with $lastWins ${lastWins == 1 ? 'win' : 'wins'}.',
            style: quiet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (figures.openTables > 0) ...[
          const SizedBox(height: 2),
          Text('A table is filling up.', style: quiet),
        ],
        FutureBuilder<MeStats?>(
          future: place,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) return const SizedBox.shrink();
            final rank = stats.rank;
            final line = rank == null
                ? 'Finish a game with 3 or more players and your name can appear here.'
                : 'You are ${_ordinal(rank)}.';
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: quiet),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PulseFigure extends StatelessWidget {
  const _PulseFigure({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _pulseCaption(LeaderboardPulse pulse) {
  if (pulse.since == null) {
    return 'Counting starts when the next ranked game finishes.';
  }
  final since =
      'Ranked games since ${_formatIstDate(pulse.since!)}. Today and this week use India time.';
  if (pulse.gamesWeek <= 0) return since;
  final games = pulse.gamesWeek == 1 ? '1 game' : '${pulse.gamesWeek} games';
  final players = pulse.playersWeek == 1
      ? '1 player'
      : '${pulse.playersWeek} players';
  return '$since $games this week, from $players.';
}

String _formatIstDate(DateTime instant) {
  final ist = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${ist.day} ${months[ist.month - 1]} ${ist.year}';
}

String _ordinal(int rank) {
  final mod100 = rank % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${rank}th';
  return switch (rank % 10) {
    1 => '${rank}st',
    2 => '${rank}nd',
    3 => '${rank}rd',
    _ => '${rank}th',
  };
}

class _BoardTable extends StatelessWidget {
  final List<LeaderboardEntry> rows;

  const _BoardTable({required this.rows});

  static const _played = 52.0;
  static const _won = 36.0;
  static const _win = 58.0;
  static const _bids = 48.0;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const SizedBox(width: 56),
              Expanded(child: Text('Name', style: headerStyle)),
              _header('Played', _played, headerStyle),
              _header('Won', _won, headerStyle),
              _header('Win%', _win, headerStyle),
              _header('Bids', _bids, headerStyle),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _BoardRow(row: rows[index]),
          ),
        ),
      ],
    );
  }

  Widget _header(String label, double width, TextStyle? style) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: style,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  final LeaderboardEntry row;

  const _BoardRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final number = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Row(
        children: [
          PlayerAvatar(
            avatarId: row.avatarId,
            nickname: row.displayName,
            radius: 18,
            boardRank: row.rank,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${row.rank}. ${row.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell('${row.games}', _BoardTable._played, number),
          _cell('${row.wins}', _BoardTable._won, number),
          _cell(row.winRateLabel, _BoardTable._win, number),
          _cell('${row.exactPercent}%', _BoardTable._bids, number),
        ],
      ),
    );
  }

  Widget _cell(String value, double width, TextStyle? style) {
    return SizedBox(
      width: width,
      child: Text(value, style: style, textAlign: TextAlign.end, maxLines: 1),
    );
  }
}

class _BoardKey extends StatefulWidget {
  const _BoardKey();

  @override
  State<_BoardKey> createState() => _BoardKeyState();
}

class _BoardKeyState extends State<_BoardKey> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Text(
                'Caps — gold is 1st, silver is 2nd, and bronze is 3rd. '
                'The same cap shows on that player\'s seat.\n'
                'A ranked game is a finished table of at least 3 players with someone signed in.\n'
                'Played — games that count, on a table with at least 3 players.\n'
                'Won — games finished in first place. A shared first counts for each player.\n'
                'Win% — wins divided by played, shown to one decimal. '
                '7 wins from 39 games is 17.9%.\n'
                'Bids — rounds where the bid matched the tricks taken. '
                '73% means 73 of every 100 rounds were exact.\n'
                'Order — most wins, then higher Win%, then higher Bids. '
                'Points per game break a remaining tie.',
                style: style,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Hide the rules' : 'How the board works'),
          ),
        ),
      ],
    );
  }
}
