import 'package:flutter/material.dart';

import '../app/app.dart';
import '../networking/api_client.dart';
import 'player_avatar.dart';

typedef ActiveGamesLoad = Future<List<ActiveGame>> Function();

/// Home screen reads this. Tests replace it so landing never hits the network.
ActiveGamesLoad activeGamesLoad = () => ApiClient().getActiveGames();

/// In-progress tables, in the same felt card as Latest game.
///
/// Shows up to four games. A fifth and beyond collapse to "N more games".
/// Renders nothing when [games] is empty. There is no room code and no join.
class LiveGamesCard extends StatelessWidget {
  const LiveGamesCard({super.key, required this.games});

  final List<ActiveGame> games;

  static const _visibleGames = 4;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) return const SizedBox.shrink();
    final shown = games.take(_visibleGames).toList();
    final extra = games.length - shown.length;
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
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE NOW',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08,
                  color: goldAccent,
                ),
              ),
              if (games.length > 1) ...[
                const Spacer(),
                Text(
                  '${games.length} games',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.55),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i == 0)
              const SizedBox(height: 12)
            else
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            _LiveTable(game: shown[i]),
          ],
          if (extra > 0) ...[
            const SizedBox(height: 10),
            Text(
              extra == 1 ? '1 more game' : '$extra more games',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: goldAccent.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveTable extends StatelessWidget {
  const _LiveTable({required this.game});

  final ActiveGame game;

  @override
  Widget build(BuildContext context) {
    final seats = game.seats;
    if (seats.isEmpty) return const SizedBox.shrink();
    final topScore = seats.first.totalScore;
    final leaders = seats.where((seat) => seat.totalScore == topScore).toList();
    final runners = seats.where((seat) => seat.totalScore != topScore).toList();
    final shared = leaders.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Round ${game.roundIndex} of ${game.totalRounds}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: ' · ${game.phaseLabel}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        _LeaderRow(leaders: leaders, shared: shared),
        if (runners.isNotEmpty) ...[
          const SizedBox(height: 6),
          _RunnersList(runners: runners, seats: seats),
        ],
        const SizedBox(height: 8),
        Text(
          shared
              ? '${seats.length} players · Shared lead'
              : '${seats.length} players',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.leaders, required this.shared});

  final List<ActiveGameSeat> leaders;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    final first = leaders.first;
    final name = shared
        ? leaders.map((seat) => seat.displayName).join(' & ')
        : first.displayName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: goldAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text(
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
            nickname: first.displayName,
            radius: 18,
            highlight: true,
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
            '${first.totalScore}',
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: goldAccent,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunnersList extends StatelessWidget {
  const _RunnersList({required this.runners, required this.seats});

  final List<ActiveGameSeat> runners;
  final List<ActiveGameSeat> seats;

  static const _visibleCount = 3;

  @override
  Widget build(BuildContext context) {
    final shown = runners.take(_visibleCount).toList();
    final overflow = runners.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final seat in shown)
          _RunnerLine(seat: seat, rank: _competitionRank(seat, seats)),
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
  const _RunnerLine({required this.seat, required this.rank});

  final ActiveGameSeat seat;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '#$rank',
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
            nickname: seat.displayName,
            radius: 13,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              seat.displayName,
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
            '${seat.totalScore}',
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

int _competitionRank(ActiveGameSeat seat, List<ActiveGameSeat> seats) {
  var better = 0;
  for (final other in seats) {
    if (other.totalScore > seat.totalScore) better++;
  }
  return better + 1;
}
