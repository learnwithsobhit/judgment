import 'package:flutter/material.dart';

import '../app/app.dart';
import '../networking/api_client.dart';
import 'leaderboard_sheet.dart';
import 'player_avatar.dart';

/// Compact "latest finished ranked game" card on the home screen.
///
/// Shows the most recent counted game's signed-in seats: winner on a gold row,
/// up to three runners-up as a vertical list (same as Live now), and a meta
/// line. Tap opens the leaderboard sheet. Renders nothing when [report] is
/// null or has no latest game, so the landing layout stays unchanged before
/// the first ranked game finishes.
class LatestGameCard extends StatelessWidget {
  const LatestGameCard({super.key, required this.report});

  final LeaderboardReport? report;

  @override
  Widget build(BuildContext context) {
    final game = report?.latestGame;
    if (game == null || game.seats.isEmpty) return const SizedBox.shrink();

    final winners = _winners(game);
    final runners = _runners(game, winners);
    final sharedFirst = winners.length > 1;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openBoard(context),
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'LATEST GAME',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08,
                    color: goldAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatWhen(game.finishedAt),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WinnerRow(winners: winners, sharedFirst: sharedFirst),
            if (runners.isNotEmpty) ...[
              const SizedBox(height: 6),
              _RunnersList(runners: runners),
            ],
            const SizedBox(height: 10),
            _MetaLine(game: game, sharedFirst: sharedFirst),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Tap to see the board ›',
                style: TextStyle(
                  fontSize: 12,
                  color: goldAccent.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Signed-in seats only. A guest who finished first is not in that list,
  /// so the card names them Guest instead of failing to draw the gold row.
  static List<_RowSeat> _winners(LatestGame game) {
    final signedIn = game.seats.where((seat) => seat.finishRank == 1).toList();
    if (signedIn.isNotEmpty) return signedIn.map(_RowSeat.account).toList();
    return const [
      _RowSeat(name: 'Guest', rank: 1, score: null, signedIn: false),
    ];
  }

  static List<_RowSeat> _runners(LatestGame game, List<_RowSeat> winners) {
    final lead = winners.first.rank;
    return game.seats
        .where((seat) => seat.finishRank != lead)
        .map(_RowSeat.account)
        .toList();
  }

  void _openBoard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const LeaderboardSheet(),
    );
  }

  String _formatWhen(DateTime finishedAt) {
    final now = DateTime.now().toUtc();
    final t = finishedAt.toUtc();
    final diff = now.difference(t);
    String rel;
    if (diff.isNegative || diff.inMinutes < 1) {
      rel = 'just now';
    } else if (diff.inHours < 1) {
      rel = '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      rel = '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      rel = '${diff.inDays}d ago';
    } else {
      rel = _formatIstDate(finishedAt);
    }
    return '$rel · ${_formatIstDate(finishedAt)}';
  }
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
  return '${ist.day} ${months[ist.month - 1]}';
}

class _RowSeat {
  const _RowSeat({
    required this.name,
    required this.rank,
    this.avatarId,
    this.photoUrl,
    required this.score,
    required this.signedIn,
  });

  final String name;
  final int rank;
  final String? avatarId;
  final String? photoUrl;
  final int? score;
  final bool signedIn;

  String get scoreLabel => score == null ? '—' : '$score';

  factory _RowSeat.account(LatestGameSeat seat) {
    return _RowSeat(
      name: seat.displayName,
      rank: seat.finishRank,
      avatarId: seat.avatarId,
      photoUrl: seat.photoUrl,
      score: seat.totalScore,
      signedIn: true,
    );
  }
}

class _WinnerRow extends StatelessWidget {
  const _WinnerRow({required this.winners, required this.sharedFirst});

  final List<_RowSeat> winners;
  final bool sharedFirst;

  @override
  Widget build(BuildContext context) {
    final first = winners.first;
    final name = sharedFirst
        ? winners.map((seat) => seat.name).join(' & ')
        : first.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: goldAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Text(
            '#1',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: goldAccent,
            ),
          ),
          const SizedBox(width: 10),
          PlayerAvatar(
            avatarId: first.avatarId,
            photoUrl: first.photoUrl,
            nickname: first.name,
            radius: 18,
            highlight: true,
            signedIn: first.signedIn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            first.scoreLabel,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: goldAccent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunnersList extends StatelessWidget {
  const _RunnersList({required this.runners});

  final List<_RowSeat> runners;

  static const _visibleCount = 3;

  @override
  Widget build(BuildContext context) {
    final shown = runners.take(_visibleCount).toList();
    final overflow = runners.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final seat in shown) _RunnerLine(seat: seat),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text(
              '+$overflow',
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    );
  }
}

class _RunnerLine extends StatelessWidget {
  const _RunnerLine({required this.seat});

  final _RowSeat seat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '#${seat.rank}',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.45),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          PlayerAvatar(
            avatarId: seat.avatarId,
            photoUrl: seat.photoUrl,
            nickname: seat.name,
            radius: 13,
            signedIn: seat.signedIn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              seat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            seat.scoreLabel,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.game, required this.sharedFirst});

  final LatestGame game;
  final bool sharedFirst;

  @override
  Widget build(BuildContext context) {
    final players = game.tableSize > game.seats.length
        ? game.tableSize
        : game.seats.length;
    final rounds = game.roundsPlayed;
    final tail = sharedFirst ? 'Shared first' : 'Ranked';
    return Text(
      '$rounds rounds · $players players · $tail',
      style: TextStyle(
        fontSize: 12,
        color: Colors.white.withValues(alpha: 0.55),
      ),
    );
  }
}
