/// Profile record. Sign out lives only here, never mid-hand.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import '../theme/festival_controller.dart';
import 'festival_admin_sheet.dart';
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

  void _openFestival() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const FestivalAdminSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountSession.instance;
    final media = MediaQuery.of(context);
    // iOS Safari paints its toolbar over the webview; padding.bottom is often
    // 0. Keep Sign out above that chrome and let the rest scroll.
    final bottomPad = math.max(media.padding.bottom, 48.0);
    final maxHeight = media.size.height * 0.72;

    final scrolling = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PlayerAvatar(
              avatarId: account.avatarId,
              photoUrl: account.photoUrl,
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
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: FestivalController.instance,
          builder: (context, _) {
            final festive = FestivalController.instance;
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: const Text('Hide festive motion'),
              subtitle: const Text('Hides floating marks. Colors stay.'),
              value: festive.calm,
              onChanged: festive.setCalm,
            );
          },
        ),
        if (account.isAdmin) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Table look',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: _openFestival,
            child: const Text('Choose festival'),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPad),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: SingleChildScrollView(child: scrolling)),
            const SizedBox(height: 8),
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
