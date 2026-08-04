import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/social_share.dart';
import 'player_avatar.dart';
import 'share_sheet.dart';

/// Full-screen party beat after the game ends — crackers + dancing avatars —
/// before the player opens the score sheet.
class VictoryCelebration extends StatefulWidget {
  final GameController controller;
  final VoidCallback onViewResults;

  const VictoryCelebration({
    super.key,
    required this.controller,
    required this.onViewResults,
  });

  @override
  State<VictoryCelebration> createState() => _VictoryCelebrationState();
}

class _VictoryCelebrationState extends State<VictoryCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _dance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final AnimationController _cracker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  final _rng = math.Random(42);
  late final List<_CrackerParticle> _particles = List.generate(48, (_) {
    return _CrackerParticle(
      x: _rng.nextDouble(),
      delay: _rng.nextDouble(),
      speed: 0.35 + _rng.nextDouble() * 0.55,
      size: 6 + _rng.nextDouble() * 10,
      color: [
        goldAccent,
        const Color(0xFFFF6B6B),
        const Color(0xFF4ECDC4),
        const Color(0xFFFFE66D),
        const Color(0xFF95E1D3),
        Colors.white,
      ][_rng.nextInt(6)],
      spin: (_rng.nextDouble() - 0.5) * 8,
    );
  });

  @override
  void dispose() {
    _dance.dispose();
    _cracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller.view!;
    final ranking = view.finalRanking ?? [];
    final winners = ranking.where((r) => r.rank == 1).toList();
    final winnerIds = winners.map((w) => w.playerId).toSet();

    final seats = <({String id, String name, String? avatar, bool winner})>[
      (
        id: widget.controller.myPlayerId,
        name: widget.controller.myNickname,
        avatar: view.ownAvatarId,
        winner: winnerIds.contains(widget.controller.myPlayerId),
      ),
      for (final o in view.opponents)
        (
          id: o.playerId,
          name: o.nickname,
          avatar: o.avatarId,
          winner: winnerIds.contains(o.playerId),
        ),
    ]..sort((a, b) {
        final ra = ranking
            .where((r) => r.playerId == a.id)
            .map((r) => r.rank)
            .firstOrNull;
        final rb = ranking
            .where((r) => r.playerId == b.id)
            .map((r) => r.rank)
            .firstOrNull;
        return (ra ?? 99).compareTo(rb ?? 99);
      });

    final headline = winners.isEmpty
        ? 'Game over!'
        : winners.length == 1
            ? '${widget.controller.nicknameOf(winners.first.playerId)} wins!'
            : 'Shared victory!';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0xFF2E7D32), feltGreenDark],
                radius: 1.1,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _cracker,
            builder: (context, _) => CustomPaint(
              painter: _CrackerPainter(
                particles: _particles,
                t: _cracker.value,
              ),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  const Text('🎉', style: TextStyle(fontSize: 42)),
                  const SizedBox(height: 8),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: goldAccent,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crackers up — enjoy the dance, then check the scores',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 36),
                  AnimatedBuilder(
                    animation: _dance,
                    builder: (context, _) {
                      return Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < seats.length; i++)
                            _DancingSeat(
                              name: seats[i].name,
                              avatarId: seats[i].avatar,
                              isWinner: seats[i].winner,
                              phase: _dance.value,
                              index: i,
                            ),
                        ],
                      );
                    },
                  ),
                  const Spacer(flex: 3),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: goldAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () => _openShare(
                      context,
                      ranking,
                      campaign: ShareCampaign.resultWin,
                      title: 'Share your win',
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text(
                      'Share win',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openShare(
                      context,
                      ranking,
                      campaign: ShareCampaign.resultChallenge,
                      title: 'Challenge friends',
                    ),
                    icon: const Icon(Icons.sports_kabaddi),
                    label: const Text('Challenge friends'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: widget.onViewResults,
                    icon: const Icon(Icons.emoji_events),
                    label: const Text('View results'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onViewResults,
                    child: Text(
                      'See round-by-round scores',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openShare(
    BuildContext context,
    List<RankedPlayer> ranking, {
    required ShareCampaign campaign,
    required String title,
  }) {
    final c = widget.controller;
    final list = ranking.isNotEmpty ? ranking : (c.view?.finalRanking ?? const []);
    final text = buildResultsShareText(
      nicknameOf: c.nicknameOf,
      myPlayerId: c.myPlayerId,
      ranking: list,
      roomCode: c.roomCode,
      campaign: campaign,
    );
    final url = (c.roomCode != null && c.roomCode!.isNotEmpty)
        ? roomInviteUrl(c.roomCode!, campaign: ShareCampaign.resultChallenge)
        : playHomeUrl(campaign: campaign);
    showSocialShareSheet(
      context: context,
      title: title,
      text: text,
      url: url,
      campaign: campaign,
      controller: c,
      ranking: list,
    );
  }
}

class _DancingSeat extends StatelessWidget {
  final String name;
  final String? avatarId;
  final bool isWinner;
  final double phase;
  final int index;

  const _DancingSeat({
    required this.name,
    required this.avatarId,
    required this.isWinner,
    required this.phase,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final bounce = math.sin((phase + index * 0.22) * math.pi) * 14;
    final tilt = math.sin((phase + index * 0.35) * math.pi * 2) * 0.18;
    final scale = isWinner ? 1.08 + phase * 0.08 : 1.0 + phase * 0.04;

    return Transform.translate(
      offset: Offset(0, -bounce),
      child: Transform.rotate(
        angle: tilt,
        child: Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (isWinner)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: goldAccent.withValues(alpha: 0.55),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  PlayerAvatar(
                    avatarId: avatarId,
                    nickname: name,
                    radius: 28,
                    highlight: isWinner,
                  ),
                  if (isWinner)
                    const Positioned(
                      top: -10,
                      child: Text('👑', style: TextStyle(fontSize: 22)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: TextStyle(
                  fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
                  color: isWinner ? goldAccent : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrackerParticle {
  final double x;
  final double delay;
  final double speed;
  final double size;
  final Color color;
  final double spin;

  const _CrackerParticle({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
  });
}

class _CrackerPainter extends CustomPainter {
  final List<_CrackerParticle> particles;
  final double t;

  _CrackerPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final progress = ((t + p.delay) % 1.0);
      final y = progress * (size.height + 40) - 20;
      final drift = math.sin((t + p.delay) * math.pi * 4) * 18;
      final cx = p.x * size.width + drift;
      final opacity = (1.0 - progress).clamp(0.15, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(cx, y);
      canvas.rotate(progress * p.spin);
      // Mini cracker shard / confetti rectangle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.45),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }

    // Occasional burst rings near top
    final burstT = (t * 2) % 1.0;
    if (burstT < 0.45) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = goldAccent.withValues(alpha: (1 - burstT / 0.45) * 0.5);
      canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.28),
        40 + burstT * 120,
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrackerPainter oldDelegate) =>
      oldDelegate.t != t;
}
