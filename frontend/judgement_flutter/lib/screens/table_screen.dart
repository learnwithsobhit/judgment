import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/card_assets.dart';
import '../widgets/assistant_panel.dart';
import '../widgets/playing_card.dart';
import '../widgets/scoreboard.dart';
import 'result_screen.dart';

/// The main game table: opponents around the felt, the current trick in the
/// middle, your hand at the bottom, bidding when it is your turn.
class TableScreen extends StatefulWidget {
  final GameController controller;

  const TableScreen({super.key, required this.controller});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  Timer? _ticker;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (controller.turnDeadline != null && mounted) setState(() {});
    });
    // Warm SVG faces/back so the first deal does not flicker.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheCardAssets(context);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final rejection = controller.lastRejection;
    final reasonCode = controller.lastRejectionCode;
    if (rejection != null && mounted) {
      controller.clearRejection();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(rejection),
        backgroundColor: const Color(0xFF8B2E2E),
        action: SnackBarAction(
          label: 'Why?',
          textColor: Colors.white,
          onPressed: () => AssistantPanel.open(
            context,
            api: controller.api,
            reasonCode: reasonCode,
            question: rejection,
          ),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.view;
        if (view == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    switch (controller.connection) {
                      GameConnectionState.connecting => 'Joining the table…',
                      GameConnectionState.reconnecting => 'Reconnecting…',
                      GameConnectionState.disconnected => 'Connection lost',
                      GameConnectionState.connected => 'Waiting for the deal…',
                    },
                  ),
                ],
              ),
            ),
          );
        }

        if (view.isFinished && view.finalRanking != null) {
          return ResultScreen(controller: controller);
        }

        final wide = MediaQuery.sizeOf(context).width >= 900;
        return Scaffold(
          endDrawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: SingleChildScrollView(
                      child: Scoreboard(controller: controller),
                    ),
                  ),
                ),
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(controller: controller, showScoreboardButton: !wide),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _TableArea(controller: controller)),
                      if (wide)
                        Container(
                          width: 280,
                          margin: const EdgeInsets.only(right: 8, bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: Scoreboard(controller: controller),
                          ),
                        ),
                    ],
                  ),
                ),
                _ActionArea(controller: controller),
                _HandArea(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar: round, trump, timer, connection
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final GameController controller;
  final bool showScoreboardButton;

  const _TopBar({required this.controller, required this.showScoreboardButton});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    final round = view.round;

    final remaining = controller.turnDeadline?.difference(DateTime.now());
    final remainingSeconds =
        remaining == null ? null : (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              if (round != null)
                Text(
                  'Round ${round.roundIndex + 1}/${round.totalRounds}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              const SizedBox(width: 12),
              if (view.trump != null) _trumpChip(view),
              const Spacer(),
              if (remainingSeconds != null && !view.isFinished) ...[
                Icon(Icons.timer_outlined,
                    size: 18,
                    color: remainingSeconds <= 10 ? Colors.orangeAccent : Colors.white70),
                const SizedBox(width: 4),
                Text(
                  '${remainingSeconds}s',
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: remainingSeconds <= 10 ? Colors.orangeAccent : Colors.white70,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              _connectionDot(controller.connection),
              IconButton(
                icon: const Icon(Icons.menu_book_outlined),
                tooltip: 'Rules assistant',
                onPressed: () => AssistantPanel.open(
                  context,
                  api: controller.api,
                ),
              ),
              if (showScoreboardButton)
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.leaderboard_outlined),
                    tooltip: 'Scoreboard',
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
            ],
          ),
          if (remaining != null && !view.isFinished)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: (remaining.inMilliseconds / controller.turnTotalMs).clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white12,
                color: remaining.inSeconds <= 10 ? Colors.orangeAccent : goldAccent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _trumpChip(PlayerGameView view) {
    final symbol = suitSymbols[view.trump] ?? '?';
    final isRed = view.trump == 'hearts' || view.trump == 'diamonds';
    return Tooltip(
      message: view.trumpCard == null
          ? 'Trump: ${view.trump}'
          : 'Trump: ${view.trump} (revealed ${view.trumpCard!.label})',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              symbol,
              style: TextStyle(
                color: isRed ? const Color(0xFFC62828) : Colors.black,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'trump',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionDot(GameConnectionState state) {
    final (color, label) = switch (state) {
      GameConnectionState.connected => (Colors.lightGreenAccent, 'Connected'),
      GameConnectionState.connecting => (Colors.amberAccent, 'Connecting'),
      GameConnectionState.reconnecting => (Colors.amberAccent, 'Reconnecting'),
      GameConnectionState.disconnected => (Colors.redAccent, 'Disconnected'),
    };
    return Semantics(
      label: 'Connection: $label',
      child: Tooltip(
        message: label,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table area: opponents around an oval, trick in the middle
// ---------------------------------------------------------------------------

class _TableArea extends StatelessWidget {
  final GameController controller;

  const _TableArea({required this.controller});

  /// Spread the viewer's opponents (3–7 of them, ADR 0003) along the top arc
  /// of the table, in clockwise order relative to the viewer's own seat.
  static Alignment _alignmentFor(int relativeIndex, int opponentCount) {
    final t = math.pi * relativeIndex / (opponentCount + 1);
    return Alignment(-math.cos(t) * 0.95, 0.55 - 1.5 * math.sin(t));
  }

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;

    // Seats can be non-contiguous, so order by seat number and rotate the
    // ring so the viewer sits at the bottom.
    final opponents = [...view.opponents]..sort((a, b) => a.seat.compareTo(b.seat));
    final relativeOrder = [
      ...opponents.where((o) => o.seat > view.ownSeat),
      ...opponents.where((o) => o.seat < view.ownSeat),
    ];

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [Color(0xFF2E7D32), feltGreen, feltGreenDark],
          stops: [0.0, 0.65, 1.0],
        ),
        borderRadius: BorderRadius.circular(160),
        border: Border.all(color: const Color(0xFF5D4037), width: 6),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: Stack(
        children: [
          for (final (index, opponent) in relativeOrder.indexed)
            Align(
              alignment: _alignmentFor(index + 1, relativeOrder.length),
              child: _OpponentSeat(
                opponent: opponent,
                isTurn: view.currentTurn == opponent.playerId,
                isDealer: view.round?.dealer == opponent.playerId,
              ),
            ),
          Align(
            alignment: const Alignment(0, 0.05),
            child: _TrickArea(controller: controller),
          ),
          // The viewer's own turn/dealer markers, shown at the bottom edge.
          Align(
            alignment: const Alignment(0, 0.97),
            child: _selfBadge(view),
          ),
        ],
      ),
    );
  }

  Widget _selfBadge(PlayerGameView view) {
    final isMyTurn = view.currentTurn == controller.myPlayerId;
    final isDealer = view.round?.dealer == controller.myPlayerId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isMyTurn ? goldAccent : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        [
          controller.myNickname,
          if (isDealer) '(dealer)',
          if (view.ownBid != null) 'bid ${view.ownBid} · won ${view.ownTricksWon}',
        ].join(' '),
        style: TextStyle(
          color: isMyTurn ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _OpponentSeat extends StatelessWidget {
  final OpponentView opponent;
  final bool isTurn;
  final bool isDealer;

  const _OpponentSeat({
    required this.opponent,
    required this.isTurn,
    required this.isDealer,
  });

  @override
  Widget build(BuildContext context) {
    final disconnected = opponent.connectionStatus == 'disconnected';
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isTurn ? goldAccent : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      disconnected ? Colors.grey.shade700 : const Color(0xFF37474F),
                  child: disconnected
                      ? const Icon(Icons.wifi_off, size: 18, color: Colors.white54)
                      : Text(
                          opponent.nickname.characters.first.toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
              if (isDealer)
                const Positioned(
                  right: -2,
                  top: -2,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: goldAccent,
                    child: Text('D',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  opponent.nickname,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  opponent.bid == null
                      ? '${opponent.cardCount} cards'
                      : 'bid ${opponent.bid} · won ${opponent.tricksWon}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrickArea extends StatelessWidget {
  final GameController controller;

  const _TrickArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    if (view.currentTrick.isEmpty) {
      final label = switch (view.phase) {
        'bidding' => 'Bidding in progress',
        'playing' => 'Waiting for the lead…',
        'round_scoring' || 'game_scoring' => 'Scoring the round…',
        _ => 'Shuffling…',
      };
      return Text(
        label,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final played in view.currentTrick)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayingCardWidget(card: played.card, width: 48),
              const SizedBox(height: 2),
              Text(
                controller.nicknameOf(played.playerId),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Action area: bidding panel or a status line
// ---------------------------------------------------------------------------

class _ActionArea extends StatelessWidget {
  final GameController controller;

  const _ActionArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    final pending = controller.pendingActionId != null;

    if (view.phase == 'bidding' && controller.isMyTurn) {
      final cards = view.round?.cardsPerPlayer ?? 0;
      final legal = view.legalActions.legalBids.toSet();
      final isDealer = view.round?.dealer == controller.myPlayerId;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Text(
              isDealer
                  ? 'Your bid — as dealer, the total cannot equal $cards'
                  : 'Your bid — how many tricks will you win?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var bid = 0; bid <= cards; bid++)
                  Semantics(
                    button: true,
                    enabled: legal.contains(bid) && !pending,
                    label: legal.contains(bid)
                        ? 'Bid $bid tricks'
                        : 'Bid $bid not allowed',
                    child: Tooltip(
                      message: legal.contains(bid)
                          ? 'Bid $bid'
                          : 'Not allowed: the dealer cannot make total bids equal $cards',
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              legal.contains(bid) ? goldAccent : Colors.white12,
                          foregroundColor:
                              legal.contains(bid) ? Colors.black : Colors.white38,
                          minimumSize: const Size(48, 44),
                        ),
                        onPressed: legal.contains(bid) && !pending
                            ? () => controller.placeBid(bid)
                            : null,
                        child: Text('$bid'),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final status = _statusText(view);
    if (status == null) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        liveRegion: true,
        label: status,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pending) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            Text(status, style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }

  String? _statusText(PlayerGameView view) {
    final turnName =
        view.currentTurn == null ? null : controller.nicknameOf(view.currentTurn!);
    return switch (view.phase) {
      'bidding' => 'Waiting for $turnName to bid…',
      'playing' => controller.isMyTurn
          ? 'Your turn — pick a card'
          : 'Waiting for $turnName to play…',
      'round_scoring' || 'game_scoring' => 'Scoring…',
      'dealing' || 'round_setup' => 'Dealing…',
      _ => null,
    };
  }
}

// ---------------------------------------------------------------------------
// Hand area
// ---------------------------------------------------------------------------

class _HandArea extends StatelessWidget {
  final GameController controller;

  const _HandArea({required this.controller});

  static const _suitDisplayOrder = ['spades', 'hearts', 'clubs', 'diamonds'];

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    if (view.ownHand.isEmpty) return const SizedBox(height: 8);

    final playable = view.legalActions.playableCards.toSet();
    final myTurnToPlay = view.phase == 'playing' && controller.isMyTurn;
    final pending = controller.pendingActionId != null;

    final hand = [...view.ownHand]..sort((a, b) {
        final suitCompare = _suitDisplayOrder
            .indexOf(a.suit)
            .compareTo(_suitDisplayOrder.indexOf(b.suit));
        if (suitCompare != 0) return suitCompare;
        return b.rankValue.compareTo(a.rankValue);
      });

    final cardWidth = MediaQuery.sizeOf(context).width < 600 ? 52.0 : 64.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final card in hand)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: PlayingCardWidget(
                  card: card,
                  width: cardWidth,
                  highlighted: myTurnToPlay && playable.contains(card.id),
                  disabled: myTurnToPlay && !playable.contains(card.id),
                  onTap: pending
                      ? null
                      : () {
                          final blocked = controller.cardBlockedReason(card);
                          if (blocked == null) {
                            controller.playCard(card.id);
                          } else {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: Text(blocked),
                                duration: const Duration(seconds: 2),
                              ));
                          }
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
