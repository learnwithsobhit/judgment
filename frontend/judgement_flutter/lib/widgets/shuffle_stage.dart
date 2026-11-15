import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../util/seat_label.dart';
import 'playing_card.dart';

/// Center-felt shuffle ritual: shared deck wash + status + countdown.
///
/// Motion is presentation only — never gates WebSocket commands.
class ShuffleStage extends StatefulWidget {
  final GameController controller;
  final double cardWidth;

  const ShuffleStage({
    super.key,
    required this.controller,
    this.cardWidth = 52,
  });

  @override
  State<ShuffleStage> createState() => _ShuffleStageState();
}

class _ShuffleStageState extends State<ShuffleStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wash;
  int? _lastIndex;
  int? _lastSeed;
  bool _catchUp = true;

  static const _washMs = 800;

  @override
  void initState() {
    super.initState();
    _wash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _washMs),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromView());
  }

  @override
  void didUpdateWidget(covariant ShuffleStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromView();
  }

  @override
  void dispose() {
    _wash.dispose();
    super.dispose();
  }

  void _syncFromView() {
    final ritual = widget.controller.view?.shuffle;
    if (ritual == null) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final index = ritual.shuffleIndex;
    final seed = ritual.animationSeed;
    if (_lastIndex == index && _lastSeed == seed) return;

    final first = _lastIndex == null;
    _lastIndex = index;
    _lastSeed = seed;

    if (reduce || (_catchUp && !first && index > 1)) {
      _wash.value = 1;
      _catchUp = false;
      return;
    }
    if (first && _catchUp && index > 1) {
      // Reconnect mid-ritual: settle without replaying every prior wash.
      _wash.value = 1;
      _catchUp = false;
      return;
    }
    _catchUp = false;
    widget.controller.playShuffleSfx();
    _wash.forward(from: 0);
  }

  bool get _washing => _wash.isAnimating;

  /// Stable 0..1 from seed + salt (no RNG during paint).
  static double _frac(int seed, int salt) {
    final x = (seed ^ (salt * 0x9e3779b9)) & 0xffff;
    return x / 0xffff;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller.view!;
    final ritual = view.shuffle;
    if (ritual == null) return const SizedBox.shrink();

    final dealerId = view.round?.dealer ?? view.currentTurn;
    final dealerName = dealerId == null
        ? 'Dealer'
        : seatLabel(widget.controller.nicknameOf(dealerId));
    final isDealer = ritual.canDeal || ritual.canShuffle;
    final vacantDealer =
        dealerId != null && widget.controller.vacantPlayerId == dealerId;

    final remaining = widget.controller.turnDeadline?.difference(DateTime.now());
    final secs = remaining == null
        ? null
        : (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);
    final progress = remaining == null || widget.controller.turnTotalMs <= 0
        ? null
        : (remaining.inMilliseconds / widget.controller.turnTotalMs).clamp(
            0.0,
            1.0,
          );

    final status = vacantDealer
        ? 'Dealing automatically…'
        : _washing
        ? 'Round ${(view.round?.roundIndex ?? 0) + 1} · $dealerName is shuffling'
        : isDealer
        ? 'Waiting for you to deal · Shuffled ×${ritual.shuffleIndex}'
        : 'Waiting for $dealerName to deal · Shuffled ×${ritual.shuffleIndex}';

    final seed = ritual.animationSeed ^ (ritual.shuffleIndex * 2654435761);

    return Semantics(
      liveRegion: true,
      label: status,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.cardWidth + 28,
              height: widget.cardWidth * 1.45 + 16,
              child: AnimatedBuilder(
                animation: _wash,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(_wash.value);
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < 5; i++)
                        Transform.translate(
                          offset: Offset(
                            (i - 2) * 2.2 +
                                math.sin(t * math.pi + i * 0.7) *
                                    (8 + _frac(seed, i) * 4) *
                                    (1 - t),
                            (i - 2).abs() * 1.2 +
                                math.cos(t * math.pi + i) *
                                    (3 + _frac(seed, i + 17) * 2) *
                                    (1 - t),
                          ),
                          child: Transform.rotate(
                            angle:
                                ((i - 2) * 0.03) +
                                math.sin(t * math.pi * 2 + i) *
                                    0.12 *
                                    (1 - t),
                            child: CardBack(width: widget.cardWidth),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (secs != null) ...[
              const SizedBox(height: 6),
              Text(
                '${secs}s',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.65),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dealer CTAs for the shuffle ritual (action band).
class ShuffleRitualActions extends StatefulWidget {
  final GameController controller;

  const ShuffleRitualActions({super.key, required this.controller});

  @override
  State<ShuffleRitualActions> createState() => _ShuffleRitualActionsState();
}

class _ShuffleRitualActionsState extends State<ShuffleRitualActions> {
  int? _lockUntilIndex;
  DateTime? _lockUntil;

  static const _lock = Duration(milliseconds: 850);

  void _armLock(int index) {
    _lockUntilIndex = index;
    _lockUntil = DateTime.now().add(_lock);
    setState(() {});
    Future<void>.delayed(_lock, () {
      if (!mounted) return;
      if (_lockUntilIndex == index) setState(() => _lockUntil = null);
    });
  }

  bool get _locked {
    final until = _lockUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller.view!;
    final ritual = view.shuffle;
    if (ritual == null || !view.isShuffleRitual) {
      return const SizedBox.shrink();
    }
    if (!ritual.canDeal && !ritual.canShuffle) {
      return const SizedBox.shrink();
    }

    final pending = widget.controller.pendingActionId != null;
    final disabled = pending || _locked;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Everyone can see this',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: disabled || !ritual.canShuffle
                      ? null
                      : () {
                          if (!reduce) _armLock(ritual.shuffleIndex);
                          widget.controller.shuffleDeck();
                        },
                  child: const Text('Shuffle again'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: disabled || !ritual.canDeal
                      ? null
                      : () {
                          if (!reduce) _armLock(ritual.shuffleIndex);
                          widget.controller.dealCards();
                        },
                  child: const Text('Deal'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
