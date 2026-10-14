/// Profile record. Sign out lives only here, never mid-hand.
library;

import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import 'player_avatar.dart';

typedef StatsLoad = Future<MeStats> Function();

StatsLoad profileStatsLoad = () {
  final api = ApiClient()..token = AccountSession.instance.token;
  return api.getMeStats();
};

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  late final Future<MeStats> _load = profileStatsLoad();
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await AccountSession.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountSession.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PlayerAvatar(
                  avatarId: account.avatarId,
                  nickname: account.displayName ?? 'Player',
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account.displayName ?? 'Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<MeStats>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Couldn\'t load your record.'),
                  );
                }
                final stats = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Played ${stats.gamesPlayed} · Won ${stats.wins} · Lost ${stats.losses}',
                    ),
                    const SizedBox(height: 6),
                    Text('Exact ${stats.exactPercent}%'),
                    const SizedBox(height: 6),
                    Text(
                      'Average score ${stats.averageScore}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _signingOut ? null : _signOut,
              child: Text(_signingOut ? 'Signing out…' : 'Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
