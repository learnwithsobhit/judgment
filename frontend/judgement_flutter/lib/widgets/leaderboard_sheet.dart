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
            Text(
              'Top players',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Wins, then exact bids, then average score',
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
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: PlayerAvatar(
                          avatarId: row.avatarId,
                          nickname: row.displayName,
                          radius: 18,
                        ),
                        title: Text(
                          '${row.rank}. ${row.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${row.wins} wins · Exact ${row.exactPercent}% · Avg ${row.averageScore}',
                        ),
                      );
                    },
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
