import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../theme/festival_controller.dart';
import '../theme/judgement_palette.dart';
import '../auth/account_session.dart';
import '../models/protocol.dart';
import '../state/game_controller.dart';
import '../util/card_assets.dart';
import '../util/game_exit_guard.dart';
import '../util/page_resume.dart';
import '../util/score_reveal.dart';
import '../util/seat_label.dart';
import '../util/table_place.dart';
import '../util/session_exit_analytics.dart';
import '../util/social_share.dart';
import '../widgets/assistant_panel.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/bid_panel.dart';
import '../widgets/cartoon_text_blast.dart';
import '../widgets/emoji_blast.dart';
import '../widgets/emote_bar.dart';
import '../widgets/festival_admin_toggle.dart';
import '../widgets/exit_confirm_dialogs.dart';
import '../widgets/player_avatar.dart';
import '../widgets/playing_card.dart';
import '../widgets/scoreboard.dart';
import '../widgets/share_sheet.dart';
import '../widgets/shuffle_stage.dart';
import '../widgets/victory_celebration.dart';
import 'fair_play_screen.dart';
import 'result_screen.dart';

/// The main game table: opponents around the felt, the current trick in the
/// middle, your hand at the bottom, bidding when it is your turn.
class TableScreen extends StatefulWidget {
  final GameController controller;

  const TableScreen({super.key, required this.controller});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> with WidgetsBindingObserver {
  Timer? _ticker;

  /// After the game ends: celebration → fair play (if eligible) → results.
  /// 0 = celebration, 1 = fair play, 2 = results.
  int _postGameStep = 0;
  bool _leaveDialogOpen = false;
  bool _leaving = false;
  String? _warmedHandKey;
  bool _deckWarmStarted = false;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    listenPageResume(() {
      controller.onAppResumed();
    });
    controller.addListener(_onControllerChanged);
    _syncExitGuard();
    _syncFestivalLock();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final clockDue =
          controller.gameStartedAt != null && controller.gameFinishedAt == null;
      if (clockDue ||
          controller.turnDeadline != null ||
          controller.pauseUntil != null ||
          controller.connection != controller.displayedConnection) {
        setState(() {});
      }
    });
    // Warm PNG faces/back so the first deal does not flicker.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeWarmDealtHand();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancelPageResume();
    setGameExitGuard(false);
    FestivalController.instance.setPlayLocked(false);
    FestivalController.instance.setCelebrationLocked(false);
    _ticker?.cancel();
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    super.dispose();
  }

  void _syncExitGuard() {
    setGameExitGuard(!_leaving && controller.shouldGuardExit);
  }

  void _syncFestivalLock() {
    final finished = controller.view?.isFinished == true;
    FestivalController.instance.setPlayLocked(!finished);
    FestivalController.instance.setCelebrationLocked(
      finished && _postGameStep == 0,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.onAppResumed();
    }
  }

  Future<void> _confirmAndLeave({required String source}) async {
    if (_leaveDialogOpen || _leaving || !controller.shouldGuardExit) return;
    _leaveDialogOpen = true;
    recordExitDialogShown(surface: ExitSurface.table, source: source);
    try {
      final leave = await showLeaveTableDialog(context);
      if (leave != true || !mounted) {
        if (leave != true) {
          recordExitStay(surface: ExitSurface.table, source: source);
        }
        return;
      }
      recordExitLeaveConfirmed(surface: ExitSurface.table, source: source);
      _leaving = true;
      setGameExitGuard(false);
      await controller.leaveGame();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      _leaveDialogOpen = false;
    }
  }

  void _maybeWarmDealtHand() {
    if (!mounted) return;
    final hand = controller.view?.ownHand ?? const <CardModel>[];
    if (hand.isEmpty) {
      _warmedHandKey = null;
      if (_deckWarmStarted) return;
      _deckWarmStarted = true;
      unawaited(
        precacheCardAssets(context, priority: const [cardBackAssetPath]),
      );
      return;
    }
    final key = hand.map(cardFaceAssetPath).join('\u0001');
    if (key == _warmedHandKey) return;
    _warmedHandKey = key;
    _deckWarmStarted = true;
    unawaited(
      precacheCardAssets(
        context,
        priority: [
          ...hand.map(cardFaceAssetPath),
          cardBackAssetPath,
        ],
      ),
    );
  }

  void _onControllerChanged() {
    _maybeWarmDealtHand();
    _syncExitGuard();
    _syncFestivalLock();
    if (_leaveDialogOpen && !controller.shouldGuardExit && mounted) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      _leaveDialogOpen = false;
    }
    final rejection = controller.lastRejection;
    final reasonCode = controller.lastRejectionCode;
    if (rejection != null && mounted) {
      controller.clearRejection();
      // Transient save/sync status uses the top progress banner, not a sticky
      // error SnackBar (which has no Cancel and keeps resurfacing on retries).
      if (rejection == 'Syncing…' ||
          rejection == 'Saving table…' ||
          rejection.startsWith('Syncing') ||
          rejection.startsWith('Saving table')) {
        return;
      }
      if (reasonCode == 'CAPACITY_FULL') {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tables are full'),
            content: Text(rejection),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final guard = !_leaving && controller.shouldGuardExit;
        final body = _buildBody(context);
        return PopScope(
          canPop: !guard,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && guard) {
              unawaited(_confirmAndLeave(source: ExitSource.back));
            }
          },
          child: body,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final view = controller.view;
    if (view == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.connection != GameConnectionState.disconnected)
                const CircularProgressIndicator()
              else
                const Icon(Icons.wifi_off, size: 40, color: Colors.white54),
              const SizedBox(height: 16),
              Text(switch (controller.connection) {
                GameConnectionState.connecting => 'Joining the table…',
                GameConnectionState.reconnecting => 'Reconnecting…',
                GameConnectionState.disconnected => 'Connection lost',
                GameConnectionState.connected => 'Waiting for the deal…',
              }),
              if (controller.canManualReconnect) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.manualReconnect,
                  child: const Text('Reconnect'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (controller.gameAborted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag, size: 48, color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  controller.endedReason ?? 'Game ended',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (view.isFinished && view.finalRanking != null) {
      _syncFestivalLock();
      if (_postGameStep >= 2) {
        return ResultScreen(controller: controller);
      }
      if (_postGameStep == 1) {
        // Same bearer as the hand — do not rebuild from AccountSession, which
        // can be empty in this tab even when the seat was account-bound.
        return FairPlayScreen(
          api: controller.api,
          gameId: controller.gameId,
          onContinue: () => setState(() {
            _postGameStep = 2;
            _syncFestivalLock();
          }),
        );
      }
      return VictoryCelebration(
        controller: controller,
        // countsForProfile is set at lobby from the live game token and stays
        // true for the whole hand; guests skip straight to results.
        onViewResults: () => setState(() {
          _postGameStep = controller.countsForProfile ? 1 : 2;
          _syncFestivalLock();
        }),
      );
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
            _TopBar(
              controller: controller,
              showScoreboardButton: !wide,
              onLeave: _leaving
                  ? null
                  : () => unawaited(
                      _confirmAndLeave(source: ExitSource.leaveButton),
                    ),
            ),
            if (controller.savingInProgress)
              Material(
                color: const Color(0xFF243B3A),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          controller.progressBannerLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.cancelPendingSave,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.pauseReason != null)
              _PauseBanner(controller: controller),
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
            if (controller.roundResultBanner != null)
              Material(
                color: goldAccent.withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    controller.roundResultBanner!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            if (controller.audioNowPlayingLabel() != null ||
                controller.audio.queueLength > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        '🎧 ${controller.audioNowPlayingLabel() ?? 'Queued'}'
                        '${controller.audio.queueLength > 1 ? ' · +${controller.audio.queueLength - 1}' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _TableActionDock(controller: controller),
            _HandArea(controller: controller),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pause / disconnect banner (reconnect grace or vacant seat)
// ---------------------------------------------------------------------------

Future<void> _confirmEndGameAsHost(
  BuildContext context,
  GameController controller,
) async {
  final end = await showEndGameDialog(context);
  if (end == true && context.mounted) {
    recordExitEndGameConfirmed();
    await controller.endGameAsHost();
  }
}

class _PauseBanner extends StatelessWidget {
  final GameController controller;

  const _PauseBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final vacant = controller.vacantPlayerId != null;
    final code = controller.vacantRoomCode ?? controller.roomCode;
    final remaining = controller.pauseUntil?.difference(DateTime.now());
    final secs = remaining == null
        ? null
        : remaining.inMilliseconds <= 0
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();

    // Soft slate/teal — calm pause signal, not alarm orange.
    const bg = Color(0xFF243B3A);
    const accent = Color(0xFF7EB8B2);
    const border = Color(0xFF3A5C58);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                vacant ? Icons.chair_alt_outlined : Icons.wifi_off_rounded,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vacant ? 'Seat open' : 'Player reconnecting',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.pauseReason ?? '',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  if (secs != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      vacant
                          ? 'Ends in ${secs}s if nobody rejoins'
                          : 'Resumes when they return · ${secs}s left',
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (vacant && !controller.amHost) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Waiting for host or a rejoin',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (vacant && code != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final text = buildLobbyInviteText(code);
                            final url = roomInviteUrl(code, medium: 'whatsapp');
                            showSocialShareSheet(
                              context: context,
                              title: 'Invite friends',
                              text: text,
                              url: url,
                              campaign: ShareCampaign.lobbyInvite,
                            );
                          },
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: const Text('Invite friends'),
                          style: FilledButton.styleFrom(
                            foregroundColor: accent,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final link = roomInviteUrl(code);
                            await Clipboard.setData(ClipboardData(text: link));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Join link copied'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: const Text('Copy join link'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: BorderSide(
                              color: accent.withValues(alpha: 0.55),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Room code $code copied'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(code),
                        ),
                        if (controller.amHost && controller.canHostRestart)
                          FilledButton(
                            onPressed: controller.restartInFlight
                                ? null
                                : () => controller.restartGameAsHost(),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: const Color(0xFF0E1F1E),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              controller.restartInFlight
                                  ? 'Restarting…'
                                  : 'Restart',
                            ),
                          ),
                        if (controller.amHost)
                          TextButton(
                            onPressed: () => unawaited(
                              _confirmEndGameAsHost(context, controller),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('End game'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar: round, game clock, trump, turn timer, connection
// ---------------------------------------------------------------------------

String _formatGameElapsed(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

String _timerPhaseHint(String phase) {
  return switch (phase) {
    'bidding' => 'Bid ',
    'playing' => 'Play ',
    'dealing' => 'Deal ',
    _ => '',
  };
}

class _TopBar extends StatelessWidget {
  final GameController controller;
  final bool showScoreboardButton;
  final VoidCallback? onLeave;

  const _TopBar({
    required this.controller,
    required this.showScoreboardButton,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    final round = view.round;

    final showTimer = controller.showsPhaseTimer;
    final remaining = showTimer
        ? controller.turnDeadline?.difference(DateTime.now())
        : null;
    final remainingSeconds = remaining == null
        ? null
        : (remaining.inMilliseconds / 1000).ceil().clamp(0, 999);

    final narrow = MediaQuery.sizeOf(context).width < 600;
    final shotUrgent = remainingSeconds != null && remainingSeconds <= 10;
    final lead = _leadChipParts(controller);
    final capsule = _statusCapsule(view, lead);
    final status = <Widget>[
      if (round != null)
        Text(
          'Round ${round.roundIndex + 1}/${round.totalRounds}',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      if (controller.gameElapsed != null) ...[
        const SizedBox(width: 8),
        Text(
          _formatGameElapsed(controller.gameElapsed!),
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
    ];
    final tools = <Widget>[
      if (remainingSeconds != null) ...[
        Icon(
          Icons.timer_outlined,
          size: 18,
          color: shotUrgent ? Colors.orangeAccent : goldAccent,
        ),
        const SizedBox(width: 4),
        Text(
          '${_timerPhaseHint(view.phase)}${remainingSeconds}s',
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: shotUrgent ? Colors.orangeAccent : goldAccent,
          ),
        ),
        const SizedBox(width: 8),
      ],
      _connectionDot(controller.displayedConnection),
      const FestivalAdminToggle(compact: true),
      if (controller.canManualReconnect)
        TextButton(
          onPressed: controller.manualReconnect,
          child: const Text('Reconnect'),
        ),
      _barButton(
        icon: Icons.menu_book_outlined,
        tooltip: 'Rules assistant',
        onPressed: () => AssistantPanel.open(context, api: controller.api),
      ),
      if (showScoreboardButton)
        Builder(
          builder: (context) => _barButton(
            icon: Icons.leaderboard_outlined,
            tooltip: 'Scoreboard',
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
      if (onLeave != null)
        _barButton(
          icon: Icons.logout,
          tooltip: 'Leave table',
          onPressed: onLeave,
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          if (narrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ...status,
                    if (capsule != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: capsule,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: tools),
              ],
            )
          else
            Row(
              children: [
                ...status,
                if (capsule != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: Align(
                    alignment: Alignment.centerLeft,
                    child: capsule,
                  )),
                ] else
                  const Spacer(),
                ...tools,
              ],
            ),
          if (remaining != null && !view.isFinished)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: (remaining.inMilliseconds / controller.turnTotalMs)
                    .clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.white12,
                color: shotUrgent ? Colors.orangeAccent : goldAccent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _barButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
    );
  }

  Widget? _statusCapsule(PlayerGameView view, _LeadParts? lead) {
    final hasTrump = view.trump != null;
    if (!hasTrump && lead == null) return null;
    if (hasTrump && lead != null) {
      return _TrumpLeadCapsule(view: view, lead: lead);
    }
    if (hasTrump) return _trumpChip(view);
    return _LeadHalf(lead: lead!);
  }

  Widget _trumpChip(PlayerGameView view) {
    return Tooltip(
      message: _trumpTooltip(view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _TrumpFace(view: view),
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

class _LeadParts {
  const _LeadParts({required this.name, required this.suffix});

  final String name;
  final String suffix;

  String get spoken => name.isEmpty ? suffix : '$name $suffix';
}

_LeadParts? _leadChipParts(GameController controller) {
  final view = controller.view;
  if (view == null) return null;
  final leader = view.leader;
  if (leader == null || view.roundHistory.isEmpty) return null;
  if (leader.margin <= 0) return const _LeadParts(name: '', suffix: 'Tied');
  final mine = leader.playerId == controller.myPlayerId;
  final name = mine
      ? 'You'
      : seatLabel(controller.nicknameOf(leader.playerId));
  if (ScoreReveal.fromView(view).showTotals) {
    return _LeadParts(name: name, suffix: '+${leader.margin}');
  }
  return _LeadParts(name: name, suffix: 'ahead');
}

String _trumpTooltip(PlayerGameView view) {
  return view.trumpCard == null
      ? 'Trump: ${view.trump}'
      : 'Trump: ${view.trump} (revealed ${view.trumpCard!.label})';
}

class _TrumpFace extends StatelessWidget {
  const _TrumpFace({required this.view, this.symbolOnly = false});

  final PlayerGameView view;
  final bool symbolOnly;

  @override
  Widget build(BuildContext context) {
    final symbol = suitSymbols[view.trump] ?? '?';
    final glyph = Text(
      symbol,
      style: TextStyle(
        color: suitColorOnLight(view.trump),
        fontSize: 16,
      ),
    );
    if (symbolOnly) return glyph;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: 4),
        Text(
          'trump',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// White trump half + gold lead half as one capsule.
class _TrumpLeadCapsule extends StatelessWidget {
  const _TrumpLeadCapsule({required this.view, required this.lead});

  final PlayerGameView view;
  final _LeadParts lead;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${_trumpTooltip(view)} · ${lead.spoken}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              ColoredBox(
                key: const ValueKey('table-trump-face'),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: _TrumpFace(view: view, symbolOnly: true),
                  ),
                ),
              ),
              const ColoredBox(color: goldAccent, child: SizedBox(width: 1)),
              Expanded(child: _LeadHalf(lead: lead, paired: true)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadHalf extends StatelessWidget {
  const _LeadHalf({required this.lead, this.paired = false});

  final _LeadParts lead;
  final bool paired;

  static const _style = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: goldAccent,
  );

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (lead.name.isNotEmpty)
          Flexible(
            child: Text(
              lead.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
          ),
        Text(
          lead.name.isEmpty ? lead.suffix : ' ${lead.suffix}',
          maxLines: 1,
          softWrap: false,
          style: _style,
        ),
      ],
    );
    final body = Semantics(
      label: lead.spoken,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: row,
      ),
    );
    if (paired) {
      return ColoredBox(
        key: const ValueKey('table-lead-chip'),
        color: feltGreen,
        child: body,
      );
    }
    return Container(
      key: const ValueKey('table-lead-chip'),
      decoration: BoxDecoration(
        color: feltGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: goldAccent.withValues(alpha: 0.45)),
      ),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Table area: opponents around an oval, trick in the middle
// ---------------------------------------------------------------------------

class _TableArea extends StatelessWidget {
  final GameController controller;

  const _TableArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;

    // Seats can be non-contiguous, so order by seat number and rotate the
    // ring so the viewer sits at the bottom. The next higher seat is on the
    // viewer's left; the rest continue clockwise.
    final opponents = [...view.opponents]
      ..sort((a, b) => a.seat.compareTo(b.seat));
    final clockwise = [
      ...opponents.where((o) => o.seat > view.ownSeat),
      ...opponents.where((o) => o.seat < view.ownSeat),
    ];
    final ring = _SeatRing.split(clockwise);
    final crowded = clockwise.length >= 6;
    final placeMarks = TablePlace.marks(view);

    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [palette.feltHighlight, palette.felt, palette.feltDark],
          stops: const [0.0, 0.65, 1.0],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.wood, width: 4),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      // Allow overall caps / peacock kalgi to paint past the felt edge.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _trickMetrics(
                  constraints.maxWidth,
                  hasSides: ring.left.isNotEmpty || ring.right.isNotEmpty,
                );
                final table = Column(
                  children: [
                    if (ring.top.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final opponent in ring.top)
                            Expanded(
                              child: _seat(
                                view,
                                opponent,
                                crowded,
                                placeMarks[opponent.playerId],
                              ),
                            ),
                        ],
                      ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sideColumn(
                            view,
                            ring.left.reversed.toList(),
                            crowded,
                            metrics.side,
                            placeMarks,
                          ),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: view.isShuffleRitual
                                  ? ShuffleStage(
                                      controller: controller,
                                      cardWidth: metrics.cardWidth,
                                    )
                                  : _TrickArea(
                                      controller: controller,
                                      cardWidth: metrics.cardWidth,
                                      columns: metrics.columns,
                                    ),
                            ),
                          ),
                          _sideColumn(
                            view,
                            ring.right,
                            crowded,
                            metrics.side,
                            placeMarks,
                          ),
                        ],
                      ),
                    ),
                    _selfBadge(
                      context,
                      view,
                      placeMarks[controller.myPlayerId],
                    ),
                  ],
                );
                if (constraints.maxHeight < 200) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: 200,
                      child: table,
                    ),
                  );
                }
                return table;
              },
            ),
          ),
          EmojiBlastOverlay(controller: controller),
          CartoonTextBlastOverlay(controller: controller),
        ],
      ),
    );
  }

  Widget _sideColumn(
    PlayerGameView view,
    List<OpponentView> seats,
    bool crowded,
    double width,
    Map<String, int> placeMarks,
  ) {
    if (seats.isEmpty) return const SizedBox(width: 4);
    // Side seats sit in a tall column; reserve headroom so kalgi/caps are not
    // clipped by the Expanded row above the avatar. Scale down when the dock
    // eats felt height (e.g. BidPanel + Confirm on a short phone).
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxHeight < 180;
          final ornamentPad = tight ? 8.0 : 28.0;
          final column = Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final opponent in seats)
                Padding(
                  padding: EdgeInsets.only(top: ornamentPad),
                  child: _seat(
                    view,
                    opponent,
                    crowded,
                    placeMarks[opponent.playerId],
                  ),
                ),
            ],
          );
          if (!tight) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final opponent in seats)
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: _seat(
                      view,
                      opponent,
                      crowded,
                      placeMarks[opponent.playerId],
                    ),
                  ),
              ],
            );
          }
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(width: width, child: column),
          );
        },
      ),
    );
  }

  Widget _seat(
    PlayerGameView view,
    OpponentView opponent,
    bool crowded,
    int? place,
  ) {
    return _OpponentSeat(
      controller: controller,
      opponent: opponent,
      isTurn: view.currentTurn == opponent.playerId,
      isDealer: view.round?.dealer == opponent.playerId,
      isLeader: view.leader?.playerId == opponent.playerId,
      pulseDealer: view.isShuffleRitual &&
          view.round?.dealer == opponent.playerId,
      avatarRadius: crowded ? 16 : 20,
      crowded: crowded,
      place: place,
    );
  }

  Future<void> _showAvatarPickerSheet(BuildContext context) async {
    final current = controller.view?.ownAvatarId;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: feltGreenDark,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change avatar',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: AvatarPicker(
                      selectedId: current,
                      photoUrl: controller.view?.ownPhotoUrl,
                      nickname: controller.myNickname,
                      autoSelectProfile:
                          AccountSession.instance.isSignedIn &&
                          (AccountSession.instance.avatarId == null ||
                              AccountSession.instance.avatarId!.isEmpty),
                      onSelected: (id) {
                        controller.setAvatar(id);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selfBadge(BuildContext context, PlayerGameView view, int? place) {
    final isMyTurn = view.currentTurn == controller.myPlayerId;
    final isDealer = view.round?.dealer == controller.myPlayerId;
    final isLeader = view.leader?.playerId == controller.myPlayerId;
    // Match crowded opponent radius so the overall cap / kalgi stays readable.
    const avatarRadius = 16.0;
    // Ornaments paint above the portrait; reserve space so they never underlap the trick.
    const ornamentReserve = avatarRadius * 1.55;
    final stats = _seatStatLine(
      bid: view.ownBid,
      tricksWon: view.ownTricksWon,
      crowded: false,
      dealerPrefix: isDealer,
    );
    final dealerBadge = isDealer
        ? const CircleAvatar(
            radius: 9,
            backgroundColor: goldAccent,
            child: Text(
              'D',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        : null;
    return Padding(
      padding: EdgeInsets.only(top: ornamentReserve, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: 'Tap to change avatar · long-press to cheer',
                child: GestureDetector(
                  onTap: () => _showAvatarPickerSheet(context),
                  child: PlayerAvatar(
                    avatarId: view.ownAvatarId,
                    photoUrl: view.ownPhotoUrl,
                    nickname: controller.myNickname,
                    radius: avatarRadius,
                    highlight: isMyTurn || isLeader,
                    boardRank: view.ownLadderRank,
                    seatOrnament: view.ownSeatOrnament,
                    signedIn: view.ownSignedIn,
                    flashMood: controller.avatarFlashes[controller.myPlayerId],
                    onLongPress: () => controller.sendAvatarFlash('cheer'),
                  ),
                ),
              ),
              if (dealerBadge != null)
                Positioned(right: -2, top: -2, child: dealerBadge),
              if (isLeader)
                const Positioned(
                  left: -2,
                  top: -2,
                  child: Text('👑', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: isMyTurn
                    ? goldAccent
                    : Colors.black.withValues(alpha: 0.55),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (place == 2 || place == 3)
                        TablePlaceRail(place: place!),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                seatLabel(controller.myNickname),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMyTurn
                                      ? Colors.black
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (stats != null)
                                Text(
                                  stats,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isMyTurn
                                        ? Colors.black87
                                        : Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glanceable seat stats after a bid. Unbid seats show the name only.
String? _seatStatLine({
  required int? bid,
  required int tricksWon,
  required bool crowded,
  bool dealerPrefix = false,
}) {
  if (bid == null) return null;
  final core = crowded
      ? 'b$bid·w$tricksWon'
      : 'bid $bid · won $tricksWon';
  if (dealerPrefix) return 'dealer · $core';
  return core;
}

/// Clockwise opponents split into left (bottom to top), top (left to right),
/// and right (top to bottom). The viewer stays below this ring.
class _SeatRing {
  final List<OpponentView> left;
  final List<OpponentView> top;
  final List<OpponentView> right;

  const _SeatRing({required this.left, required this.top, required this.right});

  static _SeatRing split(List<OpponentView> clockwise) {
    final n = clockwise.length;
    final int leftCount;
    final int rightCount;
    if (n <= 1) {
      leftCount = 0;
      rightCount = 0;
    } else if (n <= 5) {
      leftCount = 1;
      rightCount = 1;
    } else {
      leftCount = 2;
      rightCount = 2;
    }
    final topCount = n - leftCount - rightCount;
    return _SeatRing(
      left: clockwise.take(leftCount).toList(),
      top: clockwise.skip(leftCount).take(topCount).toList(),
      right: clockwise.skip(leftCount + topCount).toList(),
    );
  }
}

class _OpponentSeat extends StatelessWidget {
  final GameController controller;
  final OpponentView opponent;
  final bool isTurn;
  final bool isDealer;
  final bool isLeader;
  final bool pulseDealer;
  final double avatarRadius;
  final bool crowded;
  final int? place;

  const _OpponentSeat({
    required this.controller,
    required this.opponent,
    required this.isTurn,
    required this.isDealer,
    required this.isLeader,
    this.pulseDealer = false,
    required this.avatarRadius,
    required this.crowded,
    this.place,
  });

  @override
  Widget build(BuildContext context) {
    final disconnected =
        opponent.connectionStatus == 'disconnected' ||
        opponent.connectionStatus == 'vacant';
    final dealerBadge = isDealer
        ? CircleAvatar(
            radius: 9,
            backgroundColor: goldAccent,
            child: const Text(
              'D',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        : null;
    final stats = _seatStatLine(
      bid: opponent.bid,
      tricksWon: opponent.tricksWon,
      crowded: crowded,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              PlayerAvatar(
                avatarId: opponent.avatarId,
                photoUrl: opponent.photoUrl,
                nickname: opponent.nickname,
                radius: avatarRadius,
                highlight: isTurn || isLeader,
                muted: disconnected,
                boardRank: opponent.ladderRank,
                seatOrnament: opponent.seatOrnament,
                signedIn: opponent.signedIn,
                flashMood: controller.avatarFlashes[opponent.playerId],
                onLongPress: () =>
                    controller.sendReaction('👏', target: opponent.playerId),
              ),
              if (dealerBadge != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: pulseDealer
                      ? _SoftPulseOnce(child: dealerBadge)
                      : dealerBadge,
                ),
              if (isLeader)
                const Positioned(
                  left: -2,
                  top: -2,
                  child: Text('👑', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(
              color: isTurn
                  ? goldAccent.withValues(alpha: 0.92)
                  : Colors.black.withValues(alpha: 0.55),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (place == 2 || place == 3) TablePlaceRail(place: place!),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        child: Column(
                          children: [
                            Text(
                              seatLabel(opponent.nickname),
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isTurn ? Colors.black : Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (stats != null)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  stats,
                                  maxLines: 1,
                                  softWrap: false,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: crowded ? 11 : 12,
                                    fontWeight: FontWeight.w700,
                                    color: isTurn
                                        ? Colors.black87
                                        : Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrickMetrics {
  final double side;
  final double cardWidth;
  final int columns;

  const _TrickMetrics({
    required this.side,
    required this.cardWidth,
    required this.columns,
  });
}

/// Keep four played cards on one row on a phone. Wider tables may show more.
_TrickMetrics _trickMetrics(double inner, {required bool hasSides}) {
  const gap = 4.0;
  const maxCard = 48.0;
  if (!hasSides) {
    final columns = inner >= maxCard * 5 + gap * 4 ? 6 : 4;
    final cardWidth = math.min(
      maxCard,
      (inner - gap * (columns - 1)) / columns,
    );
    return _TrickMetrics(side: 4, cardWidth: cardWidth, columns: columns);
  }

  const minSide = 70.0;
  const maxSide = 108.0;
  final wantedCenter = maxCard * 4 + gap * 3;
  var side = (inner - wantedCenter) / 2;
  side = side.clamp(minSide, maxSide);
  final center = math.max(120.0, inner - side * 2);
  if (center >= maxCard * 5 + gap * 4) {
    final columns = ((center + gap) / (maxCard + gap)).floor().clamp(4, 8);
    return _TrickMetrics(side: side, cardWidth: maxCard, columns: columns);
  }
  final cardWidth = math
      .min(maxCard, (center - gap * 3) / 4)
      .clamp(36.0, maxCard);
  return _TrickMetrics(side: side, cardWidth: cardWidth, columns: 4);
}

class _TrickArea extends StatelessWidget {
  final GameController controller;
  final double cardWidth;
  final int columns;

  const _TrickArea({
    required this.controller,
    required this.cardWidth,
    required this.columns,
  });

  @override
  Widget build(BuildContext context) {
    final cards = controller.displayTrick;
    if (cards.isEmpty) {
      final view = controller.view!;
      // Dock owns bidding/playing wait copy — keep the felt center calm.
      final label = switch (view.phase) {
        'bidding' || 'playing' => null,
        'round_scoring' || 'game_scoring' => 'Scoring the round…',
        _ => 'Shuffling…',
      };
      if (label == null) return const SizedBox.shrink();
      return Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 14,
        ),
      );
    }
    const gap = 4.0;
    final rowWidth = cardWidth * columns + gap * (columns - 1);
    return SizedBox(
      width: rowWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.showingCompletedTrick &&
              controller.trickBanner != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                controller.trickBanner!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: goldAccent,
                  fontSize: 14,
                ),
              ),
            ),
          for (var start = 0; start < cards.length; start += columns)
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (
                    var index = start;
                    index < cards.length && index < start + columns;
                    index++
                  )
                    Padding(
                      padding: EdgeInsets.only(left: index == start ? 0 : gap),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayingCardWidget(
                            card: cards[index].card,
                            width: cardWidth,
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: cardWidth,
                            child: Text(
                              seatLabel(
                                controller.nicknameOf(cards[index].playerId),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase-aware south dock: React/Mute + primary action
// ---------------------------------------------------------------------------

class _TableActionDock extends StatelessWidget {
  final GameController controller;

  const _TableActionDock({required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    final pending = controller.pendingActionId != null;
    final myBid = view.phase == 'bidding' && controller.isMyTurn;
    final status = myBid ? null : _dockStatusText(controller, view);

    Widget? extra;
    if (view.isShuffleRitual) {
      final ritual = view.shuffle!;
      if (ritual.canDeal || ritual.canShuffle) {
        extra = ShuffleRitualActions(controller: controller);
      }
    } else if (myBid) {
      extra = _myBidPanel(context, view, pending);
    }

    return Container(
      key: const ValueKey('table-action-dock'),
      color: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmoteUnlockBanner(controller: controller),
          if (view.phase == 'bidding')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BidsSoFarBar(controller: controller),
            ),
          _DockCaptionRow(
            controller: controller,
            status: status,
            pending: pending && status != null,
          ),
          if (extra != null) extra,
        ],
      ),
    );
  }

  Widget _myBidPanel(
    BuildContext context,
    PlayerGameView view,
    bool pending,
  ) {
    final cards = view.round?.cardsPerPlayer ?? 0;
    final legal = view.legalActions.legalBids.toSet();
    final isDealer = view.round?.dealer == controller.myPlayerId;
    final dealerRestricted =
        isDealer &&
        List.generate(cards + 1, (b) => b).any((b) => !legal.contains(b));
    final panel = BidPanel(
      cards: cards,
      legalBids: legal,
      dealerRestricted: dealerRestricted,
      pending: pending,
      onConfirm: controller.placeBid,
    );
    if (MediaQuery.disableAnimationsOf(context)) return panel;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: panel,
    );
  }
}

class _DockCaptionRow extends StatelessWidget {
  final GameController controller;
  final String? status;
  final bool pending;

  const _DockCaptionRow({
    required this.controller,
    required this.status,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        EmoteReactButton(controller: controller),
        const SizedBox(width: 6),
        EmoteMicButton(controller: controller),
        Expanded(
          child: status == null
              ? const SizedBox(height: 40)
              : Semantics(
                  liveRegion: true,
                  label: status,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        Flexible(
                          child: Text(
                            status!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        EmoteMuteButton(controller: controller),
      ],
    );
  }
}

String? _dockStatusText(GameController controller, PlayerGameView view) {
  final turnName = view.currentTurn == null
      ? null
      : controller.nicknameOf(view.currentTurn!);
  return switch (view.phase) {
    'bidding' => 'Waiting for $turnName to bid…',
    'playing' =>
      controller.isMyTurn
          ? 'Your turn — pick a card'
          : 'Waiting for $turnName to play…',
    'round_scoring' || 'game_scoring' => 'Scoring…',
    'dealing' => view.isShuffleRitual ? null : 'Dealing…',
    'round_setup' => 'Dealing…',
    _ => null,
  };
}

/// Soft one-shot pulse on the dealer badge when the shuffle phase begins.
class _SoftPulseOnce extends StatefulWidget {
  final Widget child;

  const _SoftPulseOnce({required this.child});

  @override
  State<_SoftPulseOnce> createState() => _SoftPulseOnceState();
}

class _SoftPulseOnceState extends State<_SoftPulseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.18).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut),
      ),
      child: FadeTransition(
        opacity: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1, end: 0.55), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 0.55, end: 1), weight: 1),
        ]).animate(_c),
        child: widget.child,
      ),
    );
  }
}

/// One line: So far total, then compact bid pills. Scrolls sideways at 8-max.
class _BidsSoFarBar extends StatelessWidget {
  final GameController controller;

  const _BidsSoFarBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final view = controller.view!;
    final placed = <String, int>{
      for (final bid in view.bids) bid.playerId: bid.bid,
    };
    final ownBid = view.ownBid;
    if (ownBid != null) placed[controller.myPlayerId] = ownBid;
    for (final opponent in view.opponents) {
      final bid = opponent.bid;
      if (bid != null) placed[opponent.playerId] = bid;
    }
    final total = placed.values.fold<int>(0, (sum, bid) => sum + bid);
    final cards = view.round?.cardsPerPlayer;
    final soFar = cards == null ? 'So far $total' : 'So far $total / $cards';

    final roster = <({String label, int? bid, bool isTurn})>[
      for (final opponent in view.opponents)
        (
          label: seatLabel(opponent.nickname),
          bid: placed[opponent.playerId],
          isTurn: view.currentTurn == opponent.playerId,
        ),
      (
        label: 'you',
        bid: placed[controller.myPlayerId],
        isTurn: view.currentTurn == controller.myPlayerId,
      ),
    ];

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(
            soFar,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < roster.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _BidPill(
                      label: roster[i].label,
                      bid: roster[i].bid,
                      isTurn: roster[i].isTurn,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BidPill extends StatelessWidget {
  const _BidPill({
    required this.label,
    required this.bid,
    required this.isTurn,
  });

  final String label;
  final int? bid;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: isTurn ? Border.all(color: goldAccent, width: 1) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          '$label ${bid ?? '—'}',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
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

    final hand = [...view.ownHand]
      ..sort((a, b) {
        final suitCompare = _suitDisplayOrder
            .indexOf(a.suit)
            .compareTo(_suitDisplayOrder.indexOf(b.suit));
        if (suitCompare != 0) return suitCompare;
        return b.rankValue.compareTo(a.rankValue);
      });

    final cardWidth = MediaQuery.sizeOf(context).width < 600 ? 52.0 : 64.0;

    // Fully opaque immediately — never hide faces during bidding/play.
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
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(blocked),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
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
