import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import 'player_avatar.dart';

/// Felt/gold trophy card for Stories / download (1080×1920 logical scaled).
class ShareResultCard extends StatelessWidget {
  final GameController controller;
  final List<RankedPlayer> ranking;
  final String? nightLine;
  final GlobalKey boundaryKey;

  /// Logical size; capture at devicePixelRatio for crisp PNG.
  final Size logicalSize;

  const ShareResultCard({
    super.key,
    required this.controller,
    required this.ranking,
    required this.boundaryKey,
    this.nightLine,
    this.logicalSize = const Size(360, 640),
  });

  @override
  Widget build(BuildContext context) {
    final winners = ranking.where((r) => r.rank == 1).toList();
    final myRank = ranking
        .where((r) => r.playerId == controller.myPlayerId)
        .map((r) => r.rank)
        .firstOrNull;
    final headline = winners.isEmpty
        ? 'Game over'
        : winners.length == 1
            ? '${controller.nicknameOf(winners.first.playerId)} wins!'
            : 'Shared victory!';
    final top = ranking.take(3).toList();

    return RepaintBoundary(
      key: boundaryKey,
      child: SizedBox(
        width: logicalSize.width,
        height: logicalSize.height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [feltGreen, feltGreenDark],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'JUDGEMENT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: goldAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bid. Trump. Brag.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.emoji_events, size: 56, color: goldAccent),
                const SizedBox(height: 12),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                if (myRank != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: goldAccent.withValues(alpha: 0.7),
                        ),
                        color: goldAccent.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        'You placed #$myRank',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: goldAccent,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final ranked in _podiumOrder(top))
                      _SharePodiumSeat(
                        controller: controller,
                        ranked: ranked,
                      ),
                  ],
                ),
                if (nightLine != null && nightLine!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    nightLine!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Play free with friends',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: goldAccent,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'judgment-lws-260731.web.app',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '#JudgementTable',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<RankedPlayer> _podiumOrder(List<RankedPlayer> top) {
    if (top.length >= 3) return [top[1], top[0], top[2]];
    return top;
  }
}

class _SharePodiumSeat extends StatelessWidget {
  final GameController controller;
  final RankedPlayer ranked;

  const _SharePodiumSeat({
    required this.controller,
    required this.ranked,
  });

  @override
  Widget build(BuildContext context) {
    final elevate = ranked.rank == 1;
    final name = controller.nicknameOf(ranked.playerId);
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#${ranked.rank}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: elevate ? goldAccent : Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          PlayerAvatar(
            avatarId: controller.avatarOf(ranked.playerId),
            nickname: name,
            radius: elevate ? 28 : 22,
            highlight: elevate,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            '${ranked.totalScore}',
            style: TextStyle(
              fontSize: elevate ? 20 : 16,
              fontWeight: FontWeight.w900,
              color: goldAccent,
            ),
          ),
        ],
      ),
    );
  }
}

Future<Uint8List?> captureShareCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      // Never call debugNeedsPaint here — it throws in release/profile builds.
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (_) {
      // Layer not ready yet — wait and retry.
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return null;
}
