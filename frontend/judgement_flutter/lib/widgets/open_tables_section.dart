import 'package:flutter/material.dart';

import '../networking/api_client.dart';
import 'player_avatar.dart';

/// Waiting tables on Join room. The code box stays below this.
class OpenTablesSection extends StatelessWidget {
  const OpenTablesSection({
    super.key,
    required this.signedIn,
    required this.tables,
    required this.onJoin,
  });

  final bool signedIn;
  final List<OpenTable> tables;
  final ValueChanged<OpenTable> onJoin;

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('Sign in to see tables that are waiting.'),
      );
    }
    if (tables.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'No table is waiting. Ask someone to create a room, or enter a code.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final table in tables) ...[
          _OpenTableRow(table: table, onJoin: () => onJoin(table)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OpenTableRow extends StatelessWidget {
  const _OpenTableRow({required this.table, required this.onJoin});

  final OpenTable table;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final withNames = table.withNames.isEmpty
        ? null
        : 'with ${table.withNames.join(' and ')}';
    final seats =
        '${table.seated} of ${table.maxPlayers} seated, ${table.seatsOpen} open';
    return Row(
      children: [
        PlayerAvatar(
          avatarId: table.hostAvatarId,
          nickname: table.hostNickname,
          radius: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (table.yours)
                Text(
                  "You're at this table",
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              Text(
                table.hostNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (withNames != null)
                Text(
                  withNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(seats, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        TextButton(
          onPressed: onJoin,
          child: Text(table.yours ? 'Open' : 'Join'),
        ),
      ],
    );
  }
}
