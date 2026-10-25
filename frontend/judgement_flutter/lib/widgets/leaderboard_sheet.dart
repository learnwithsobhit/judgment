/// Public Top 10. Empty and failure stay inside this sheet.
library;

import 'package:flutter/material.dart';

import '../networking/api_client.dart';
import 'player_avatar.dart';

typedef LeaderboardLoad = Future<List<LeaderboardEntry>> Function();

LeaderboardLoad leaderboardLoad = () => ApiClient().getLeaderboard();

class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key});

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet> {
  late final Future<List<LeaderboardEntry>> _load = leaderboardLoad();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Top players', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Most wins, then win rate, then bid rate',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<LeaderboardEntry>>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Couldn\'t load the board. You can still play.',
                    ),
                  );
                }
                final rows = snapshot.data ?? const <LeaderboardEntry>[];
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No ranked games yet.'),
                  );
                }
                return Flexible(
                  child: Column(
                    children: [
                      Expanded(child: _BoardTable(rows: rows)),
                      const SizedBox(height: 12),
                      const _BoardKey(),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardTable extends StatelessWidget {
  final List<LeaderboardEntry> rows;

  const _BoardTable({required this.rows});

  static const _played = 52.0;
  static const _won = 36.0;
  static const _win = 48.0;
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
          _cell('${row.winPercent}%', _BoardTable._win, number),
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

class _BoardKey extends StatelessWidget {
  const _BoardKey();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      height: 1.35,
    );
    return Text(
      'Caps — gold is 1st, silver is 2nd, and bronze is 3rd. '
      'The same cap shows on that player\'s seat.\n'
      'Played — games that count, on a table with at least 3 players.\n'
      'Won — games finished in first place. A shared first counts for each player.\n'
      'Win% — wins divided by played, times 100.\n'
      'Bids — rounds where the bid matched the tricks taken. '
      '73% means 73 of every 100 rounds were exact.\n'
      'Order — most wins, then higher Win%, then higher Bids. '
      'Points per game break a remaining tie.',
      style: style,
    );
  }
}
