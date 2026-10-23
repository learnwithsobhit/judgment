import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../util/social_share.dart';
import '../widgets/share_sheet.dart';

/// Shown to someone who created a room they will not play.
/// They are not seated; the first person who opens the link becomes host.
class SetupRoomScreen extends StatelessWidget {
  final String code;
  final int seats;

  const SetupRoomScreen({
    super.key,
    required this.code,
    required this.seats,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Room ready')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share this with the $seats players. '
                'You are not in the game.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: goldAccent,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The first person who joins becomes host. '
                'Everyone taps Ready, and the host can start once at least 3 players are ready.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  showSocialShareSheet(
                    context: context,
                    title: 'Invite friends',
                    text: buildLobbyInviteText(code),
                    url: roomInviteUrl(code, medium: 'whatsapp'),
                    campaign: ShareCampaign.lobbyInvite,
                  );
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Invite friends'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: roomInviteUrl(code)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Join link copied')),
                  );
                },
                icon: const Icon(Icons.link),
                label: const Text('Copy link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
