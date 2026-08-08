import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/spectator_controller.dart';
import '../widgets/player_avatar.dart';

/// Audience-facing standings after a natural finish (no coach / rematch).
class SpectatorResultScreen extends StatelessWidget {
  final SpectatorController controller;

  const SpectatorResultScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    final ranking = view?.finalRanking ?? const <RankedPlayer>[];
    final history = view?.roundHistory ?? const <RoundScoreView>[];
    final winners = ranking.where((r) => r.rank == 1).toList();
    final crowdLine = _crowdOutcomeLine(controller, winners);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [feltGreen, feltGreenDark],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroBanner(controller: controller, winners: winners),
                  if (crowdLine != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: goldAccent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        crowdLine,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: goldAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (ranking.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _PodiumStrip(controller: controller, ranking: ranking),
                    const SizedBox(height: 28),
                    Text(
                      'Final standings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _StandingsTable(controller: controller, ranking: ranking),
                  ],
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Round-by-round',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...history.map((round) {
                      final entries = round.entries
                          .map((e) =>
                              '${controller.nicknameOf(e.playerId)} ${e.score >= 0 ? '+' : ''}${e.score} (bid ${e.bid}, won ${e.tricksWon})')
                          .join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'R${round.roundIndex + 1}: $entries',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.home),
                    label: const Text('Back to home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _crowdOutcomeLine(
  SpectatorController controller,
  List<RankedPlayer> winners,
) {
  final crowd = controller.crowdPrediction;
  if (crowd == null || crowd.totalVoters == 0 || crowd.tallies.isEmpty) {
    return null;
  }
  if (winners.isEmpty) return null;
  final winnerIds = winners.map((w) => w.playerId).toSet();
  final topPick = crowd.tallies.first;
  final pickName = controller.nicknameOf(topPick.playerId);
  final calledIt = winnerIds.contains(topPick.playerId);
  if (calledIt) {
    return 'Crowd called it — $pickName (${topPick.count}/${crowd.totalVoters})';
  }
  final actual = winners.map((w) => controller.nicknameOf(w.playerId)).join(', ');
  return 'Crowd missed — backed $pickName, winner was $actual';
}

class _HeroBanner extends StatelessWidget {
  final SpectatorController controller;
  final List<RankedPlayer> winners;

  const _HeroBanner({required this.controller, required this.winners});

  @override
  Widget build(BuildContext context) {
    final headline = winners.isEmpty
        ? 'Game over'
        : winners.length == 1
            ? '${controller.nicknameOf(winners.first.playerId)} wins!'
            : 'Shared victory: ${winners.map((w) => controller.nicknameOf(w.playerId)).join(', ')}';

    return Column(
      children: [
        const Icon(Icons.emoji_events, size: 72, color: goldAccent),
        const SizedBox(height: 10),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You watched this table',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PodiumStrip extends StatelessWidget {
  final SpectatorController controller;
  final List<RankedPlayer> ranking;

  const _PodiumStrip({required this.controller, required this.ranking});

  @override
  Widget build(BuildContext context) {
    final top = ranking.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final display = top.length >= 3 ? [top[1], top[0], top[2]] : top;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final ranked in display)
          Expanded(
            child: _PodiumSeat(
              controller: controller,
              ranked: ranked,
              elevate: ranked.rank == 1,
            ),
          ),
      ],
    );
  }
}

class _PodiumSeat extends StatelessWidget {
  final SpectatorController controller;
  final RankedPlayer ranked;
  final bool elevate;

  const _PodiumSeat({
    required this.controller,
    required this.ranked,
    required this.elevate,
  });

  Color get _medal {
    switch (ranked.rank) {
      case 1:
        return goldAccent;
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = controller.nicknameOf(ranked.playerId);
    return Padding(
      padding: EdgeInsets.only(left: 4, right: 4, bottom: elevate ? 0 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#${ranked.rank}',
            style: TextStyle(
              fontSize: elevate ? 18 : 14,
              fontWeight: FontWeight.w800,
              color: _medal,
            ),
          ),
          const SizedBox(height: 6),
          PlayerAvatar(
            avatarId: controller.avatarOf(ranked.playerId),
            nickname: name,
            radius: elevate ? 28 : 22,
            highlight: ranked.rank == 1,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: ranked.rank == 1 ? FontWeight.w700 : FontWeight.w500,
              fontSize: elevate ? 14 : 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${ranked.totalScore}',
            style: TextStyle(
              fontSize: elevate ? 22 : 18,
              fontWeight: FontWeight.w800,
              color: _medal,
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  final SpectatorController controller;
  final List<RankedPlayer> ranking;

  const _StandingsTable({required this.controller, required this.ranking});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final ranked in ranking)
            ListTile(
              dense: true,
              leading: Text(
                '#${ranked.rank}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: ranked.rank == 1 ? goldAccent : Colors.white70,
                ),
              ),
              title: Text(controller.nicknameOf(ranked.playerId)),
              subtitle: Text(
                'Exact bids ${ranked.exactBidRounds} · Missed ${ranked.totalTricksMissed}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Text(
                '${ranked.totalScore}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
