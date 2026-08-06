import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../embed/judgement_embed_scope.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/social_share.dart';
import '../widgets/player_avatar.dart';
import '../widgets/round_score_matrix.dart';
import '../widgets/share_sheet.dart';

/// Client-only celebration + standings from the last WS [PlayerGameView].
class ResultScreen extends StatelessWidget {
  final GameController controller;

  const ResultScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    final ranking = view?.finalRanking ?? [];
    final history = view?.roundHistory ?? const <RoundScoreView>[];
    final winners = ranking.where((r) => r.rank == 1).toList();
    final myRank = ranking
        .where((r) => r.playerId == controller.myPlayerId)
        .map((r) => r.rank)
        .firstOrNull;
    final night = _YourNightStats.from(
      myPlayerId: controller.myPlayerId,
      ranking: ranking,
      history: history,
    );

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
                  _HeroBanner(
                    controller: controller,
                    winners: winners,
                    myRank: myRank,
                  ),
                  if (ranking.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _PodiumStrip(controller: controller, ranking: ranking),
                    const SizedBox(height: 28),
                    Text(
                      'Final standings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _StandingsTable(
                      controller: controller,
                      ranking: ranking,
                    ),
                  ],
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Round-by-round',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Exact bid = 10 + bid · miss = 0',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _RoundVerifyMatrix(
                          controller: controller,
                          ranking: ranking,
                          history: history,
                        ),
                      ),
                    ),
                  ],
                  if (night != null) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Your night',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _YourNightSection(stats: night),
                  ],
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: ranking.isEmpty
                            ? null
                            : () {
                                final nightLine = night == null
                                    ? null
                                    : _nightShareLine(night);
                                final text = buildResultsShareText(
                                  nicknameOf: controller.nicknameOf,
                                  myPlayerId: controller.myPlayerId,
                                  ranking: ranking,
                                  nightLine: nightLine,
                                  roomCode: controller.roomCode,
                                  campaign: ShareCampaign.resultWin,
                                );
                                final url = (controller.roomCode != null &&
                                        controller.roomCode!.isNotEmpty)
                                    ? roomInviteUrl(
                                        controller.roomCode!,
                                        campaign:
                                            ShareCampaign.resultChallenge,
                                      )
                                    : playHomeUrl(
                                        campaign: ShareCampaign.resultWin,
                                      );
                                showSocialShareSheet(
                                  context: context,
                                  title: 'Share results',
                                  text: text,
                                  url: url,
                                  campaign: ShareCampaign.resultWin,
                                  controller: controller,
                                  ranking: ranking,
                                  nightLine: nightLine,
                                );
                              },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share'),
                      ),
                      OutlinedButton.icon(
                        onPressed: ranking.isEmpty
                            ? null
                            : () async {
                                final text = buildResultsShareText(
                                  nicknameOf: controller.nicknameOf,
                                  myPlayerId: controller.myPlayerId,
                                  ranking: ranking,
                                  nightLine: night == null
                                      ? null
                                      : _nightShareLine(night),
                                  roomCode: controller.roomCode,
                                );
                                await Clipboard.setData(
                                  ClipboardData(text: text),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Results copied'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy results summary'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            JudgementEmbedScope.exitToHome(context),
                        icon: const Icon(Icons.home),
                        label: Text(JudgementEmbedScope.backHomeLabel(context)),
                      ),
                    ],
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

String _nightShareLine(_YourNightStats night) {
  final parts = <String>[];
  if (night.bestExactScore != null) {
    parts.add('best exact ${night.bestExactScore}');
  }
  parts.add('${night.missCount} misses');
  if (night.marginVsWinner != null) {
    parts.add('${night.marginVsWinner} behind winner');
  }
  return 'Your night: ${parts.join(' · ')}';
}

class _HeroBanner extends StatelessWidget {
  final GameController controller;
  final List<RankedPlayer> winners;
  final int? myRank;

  const _HeroBanner({
    required this.controller,
    required this.winners,
    required this.myRank,
  });

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
        if (myRank != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: goldAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: goldAccent.withValues(alpha: 0.55)),
            ),
            child: Text(
              'You placed #$myRank',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: goldAccent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PodiumStrip extends StatelessWidget {
  final GameController controller;
  final List<RankedPlayer> ranking;

  const _PodiumStrip({
    required this.controller,
    required this.ranking,
  });

  @override
  Widget build(BuildContext context) {
    final top = ranking.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    // Display order: 2nd, 1st, 3rd when we have 3; otherwise natural.
    final display = top.length >= 3
        ? [top[1], top[0], top[2]]
        : top;

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
  final GameController controller;
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
    final you = ranked.playerId == controller.myPlayerId;

    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        bottom: elevate ? 0 : 12,
      ),
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
            you ? '$name (you)' : name,
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
  final GameController controller;
  final List<RankedPlayer> ranking;

  const _StandingsTable({
    required this.controller,
    required this.ranking,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Player')),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(
              label: Tooltip(
                message:
                    'Rounds where the bid was hit exactly (first tie-break)',
                child: Text('Exact rounds'),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Tooltip(
                message:
                    'Total tricks off from the bid (second tie-break)',
                child: Text('Tricks missed'),
              ),
              numeric: true,
            ),
          ],
          rows: [
            for (final ranked in ranking)
              DataRow(
                color: ranked.rank == 1
                    ? WidgetStatePropertyAll(
                        goldAccent.withValues(alpha: 0.15),
                      )
                    : null,
                cells: [
                  DataCell(Text('${ranked.rank}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlayerAvatar(
                          avatarId: controller.avatarOf(ranked.playerId),
                          nickname: controller.nicknameOf(ranked.playerId),
                          radius: 12,
                          highlight: ranked.rank == 1,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          controller.nicknameOf(ranked.playerId) +
                              (ranked.playerId == controller.myPlayerId
                                  ? ' (you)'
                                  : ''),
                          style: TextStyle(
                            fontWeight: ranked.rank == 1
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(
                    '${ranked.totalScore}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
                  DataCell(Text('${ranked.exactBidRounds}')),
                  DataCell(Text('${ranked.totalTricksMissed}')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _YourNightStats {
  final int? bestExactScore;
  final int? bestExactRound; // 1-based
  final int missCount;
  final int longestMissStreak;
  final int? marginVsWinner; // null if viewer won or tied for first

  const _YourNightStats({
    required this.bestExactScore,
    required this.bestExactRound,
    required this.missCount,
    required this.longestMissStreak,
    required this.marginVsWinner,
  });

  static _YourNightStats? from({
    required String myPlayerId,
    required List<RankedPlayer> ranking,
    required List<RoundScoreView> history,
  }) {
    if (ranking.isEmpty && history.isEmpty) return null;

    int? bestExactScore;
    int? bestExactRound;
    var missCount = 0;
    var longestMiss = 0;
    var streak = 0;

    for (final r in history) {
      RoundScoreLine? line;
      for (final e in r.entries) {
        if (e.playerId == myPlayerId) {
          line = e;
          break;
        }
      }
      if (line == null) continue;
      final exact = line.bid == line.tricksWon;
      if (exact) {
        streak = 0;
        if (bestExactScore == null || line.score > bestExactScore) {
          bestExactScore = line.score;
          bestExactRound = r.roundIndex + 1;
        }
      } else {
        missCount++;
        streak++;
        if (streak > longestMiss) longestMiss = streak;
      }
    }

    final me = ranking.where((r) => r.playerId == myPlayerId).firstOrNull;
    final winnerScore = ranking
        .where((r) => r.rank == 1)
        .map((r) => r.totalScore)
        .firstOrNull;
    int? margin;
    if (me != null && winnerScore != null && me.rank > 1) {
      margin = winnerScore - me.totalScore;
    }

    return _YourNightStats(
      bestExactScore: bestExactScore,
      bestExactRound: bestExactRound,
      missCount: missCount,
      longestMissStreak: longestMiss,
      marginVsWinner: margin,
    );
  }
}

class _YourNightSection extends StatelessWidget {
  final _YourNightStats stats;

  const _YourNightSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (stats.bestExactScore != null)
        _NightCard(
          label: 'Best exact',
          value: '${stats.bestExactScore} pts',
          detail: 'Round ${stats.bestExactRound}',
        )
      else
        const _NightCard(
          label: 'Best exact',
          value: '—',
          detail: 'No exact rounds',
        ),
      _NightCard(
        label: 'Misses',
        value: '${stats.missCount}',
        detail: stats.longestMissStreak > 0
            ? 'Longest streak ${stats.longestMissStreak}'
            : 'No miss streak',
      ),
      if (stats.marginVsWinner != null)
        _NightCard(
          label: 'Vs winner',
          value: '−${stats.marginVsWinner}',
          detail: 'points behind',
        )
      else
        const _NightCard(
          label: 'Vs winner',
          value: 'Top',
          detail: 'You finished first',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

class _NightCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;

  const _NightCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: goldAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundVerifyMatrix extends StatelessWidget {
  final GameController controller;
  final List<RankedPlayer> ranking;
  final List<RoundScoreView> history;

  const _RoundVerifyMatrix({
    required this.controller,
    required this.ranking,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final playerIds = ranking.map((r) => r.playerId).toList();
    if (playerIds.isEmpty) {
      final view = controller.view!;
      playerIds.add(controller.myPlayerId);
      playerIds.addAll(view.opponents.map((o) => o.playerId));
    }

    return RoundScoreMatrix(
      columns: [
        for (final playerId in playerIds)
          RoundScoreColumn(
            playerId: playerId,
            displayName: controller.nicknameOf(playerId),
            avatarId: controller.avatarOf(playerId),
            highlightHeader: playerId == controller.myPlayerId,
            total: _columnSum(playerId),
          ),
      ],
      history: history,
      showTotals: true,
      roundHeaderLabel: 'Rnd',
      totalsLabel: 'TOTAL',
      cellTooltip: _roundTooltip,
    );
  }

  int _columnSum(String playerId) {
    var sum = 0;
    for (final r in history) {
      for (final e in r.entries) {
        if (e.playerId == playerId) sum += e.score;
      }
    }
    return sum;
  }

  String _roundTooltip(RoundScoreView round, String playerId) {
    for (final e in round.entries) {
      if (e.playerId == playerId) {
        return '${controller.nicknameOf(playerId)} · R${round.roundIndex + 1}: '
            'bid ${e.bid} → won ${e.tricksWon} → ${e.score} pts';
      }
    }
    return 'No score';
  }
}
