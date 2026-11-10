import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../networking/api_client.dart';
import 'player_avatar.dart';

typedef AvailabilityLoad = Future<AvailabilityBoard> Function();

/// Home screen reads this. Tests replace it so landing never hits the network.
AvailabilityLoad availabilityLoad = () => ApiClient().getAvailability();

/// Signed-in players who are free to play right now.
///
/// Empty, waiting, and ready states share the Live now shell. Guests see the
/// list; only a signed-in account can flip the switch.
class WhosFreeCard extends StatelessWidget {
  const WhosFreeCard({
    super.key,
    required this.board,
    required this.signedIn,
    this.myUserId,
    this.saving = false,
    this.saveError,
    this.onToggle,
    this.onStartTable,
  });

  final AvailabilityBoard board;
  final bool signedIn;
  final String? myUserId;
  final bool saving;
  final String? saveError;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onStartTable;

  static const _visiblePeople = 4;

  bool get _available {
    final id = myUserId;
    if (id == null || id.isEmpty) return false;
    return board.players.any((player) => player.userId == id);
  }

  @override
  Widget build(BuildContext context) {
    final shown = board.players.take(_visiblePeople).toList();
    final extra = board.players.length - shown.length;
    final needed = (3 - board.count).clamp(0, 3);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'WHO\'S FREE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08,
                  color: goldAccent,
                ),
              ),
              const Spacer(),
              Text(
                '${board.count}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(
              'No one is free yet.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            )
          else
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shown.length + (extra > 0 ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index >= shown.length) {
                    return _MoreLabel(extra: extra);
                  }
                  final player = shown[index];
                  final mine = player.userId == myUserId;
                  return _FreePerson(
                    name: mine ? 'You' : player.displayName,
                    avatarId: player.avatarId,
                    photoUrl: player.photoUrl,
                  );
                },
              ),
            ),
          if (board.count > 0 && board.count < 3) ...[
            const SizedBox(height: 10),
            Text(
              needed == 1 ? 'Need 1 more.' : 'Need $needed more.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (board.ready) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: goldAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: goldAccent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ready to play.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: onStartTable,
                      child: const Text('Start a table'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (signedIn)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'I\'m free',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (_available)
                        Text(
                          'For the next 90 minutes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: _available,
                  onChanged: saving || onToggle == null
                      ? null
                      : (value) => onToggle!(value),
                ),
              ],
            )
          else
            Text(
              'Sign in to mark yourself free.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          if (saveError != null) ...[
            const SizedBox(height: 6),
            Text(
              saveError!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FreePerson extends StatelessWidget {
  const _FreePerson({
    required this.name,
    required this.avatarId,
    required this.photoUrl,
  });

  final String name;
  final String? avatarId;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          PlayerAvatar(
            avatarId: avatarId,
            photoUrl: photoUrl,
            nickname: name,
            radius: 18,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreLabel extends StatelessWidget {
  const _MoreLabel({required this.extra});

  final int extra;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Text(
        extra == 1 ? '1 more' : '$extra more',
        style: TextStyle(
          fontSize: 12,
          color: goldAccent.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
