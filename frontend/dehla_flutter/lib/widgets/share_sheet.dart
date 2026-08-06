import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dehla_theme.dart';
import '../util/room_share.dart';

Future<void> showDehlaInviteSheet(
  BuildContext context, {
  required String code,
}) async {
  final url = dehlaRoomInviteUrl(code: code);
  final text = buildDehlaLobbyInviteText(code: code, url: url);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: feltGreenDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Invite friends',
            style: TextStyle(
              color: goldAccent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Join link copied')),
                );
              }
            },
            icon: const Icon(Icons.link),
            label: const Text('Copy join link'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')),
                );
              }
            },
            icon: const Icon(Icons.tag),
            label: const Text('Copy code'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite text copied')),
                );
              }
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('Copy invite message'),
          ),
        ],
      ),
    ),
  );
}
