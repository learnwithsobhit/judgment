import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../networking/game_socket.dart';
import '../theme/dehla_theme.dart';
import '../util/analytics.dart';
import '../util/game_reclaim_store.dart';
import '../util/i18n.dart';
import '../util/room_share.dart';
import '../widgets/exit_confirm_dialogs.dart';
import '../widgets/pile_hud.dart';
import '../widgets/player_avatar.dart';
import '../widgets/playing_card.dart';
import '../widgets/share_sheet.dart';
import 'lobby_screen.dart';

class DehlaTableScreen extends StatefulWidget {
  const DehlaTableScreen({
    super.key,
    required this.api,
    required this.gameId,
    required this.playerId,
    this.roomCode,
    this.isHost = false,
    this.nickname = '',
  });

  final DehlaApiClient api;
  final String gameId;
  final String playerId;
  final String? roomCode;
  final bool isHost;
  final String nickname;

  @override
  State<DehlaTableScreen> createState() => _DehlaTableScreenState();
}

class _DehlaTableScreenState extends State<DehlaTableScreen> {
  DehlaGameSocket? _socket;
  PlayerGameView? _view;
  String? _reject;
  bool _hostBusy = false;
  bool _leavingForLobby = false;

  @override
  void initState() {
    super.initState();
    _socket = DehlaGameSocket(
      urlBuilder: () => widget.api.wsUrl(widget.gameId),
      onView: (v) {
        setState(() {
          _view = v;
          _reject = null;
        });
        if (v.phase == 'match_complete') {
          trackDehlaEvent('match_completed', {'winner': v.matchWinner});
        }
      },
      onToken: (t) {
        widget.api.token = t;
        final code = widget.roomCode;
        if (code != null) {
          final existing = readGameReclaim(code);
          if (existing != null) {
            writeGameReclaim(
              GameReclaimBlob(
                token: t,
                sessionId: existing.sessionId,
                roomCode: existing.roomCode,
                playerId: existing.playerId,
                gameId: existing.gameId ?? widget.gameId,
                nickname: existing.nickname,
                savedAt: DateTime.now().toUtc(),
              ),
            );
          }
        }
      },
      onReject: (r) => setState(() => _reject = r),
      onGameEnded: (reason, aborted) {
        trackDehlaEvent('game_ended', {'reason': reason, 'aborted': aborted});
        _returnToLobby();
      },
      onGameRestarted: (gameId) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DehlaTableScreen(
              api: widget.api,
              gameId: gameId,
              playerId: widget.playerId,
              roomCode: widget.roomCode,
              isHost: widget.isHost,
              nickname: widget.nickname,
            ),
          ),
        );
      },
    )..connect();
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }

  bool _isPlayable(CardModel c) {
    final v = _view;
    if (v == null ||
        v.paused ||
        v.phase == 'hand_complete' ||
        v.phase == 'match_complete') {
      return false;
    }
    return v.playable.any((x) => x.suit == c.suit && x.rank == c.rank);
  }

  Future<void> _returnToLobby() async {
    if (_leavingForLobby || !mounted) return;
    _leavingForLobby = true;
    await _socket?.close();
    final code = widget.roomCode;
    if (code == null || !mounted) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    try {
      final room = await widget.api.getRoom(code);
      if (!mounted) return;
      final isHost = room.seats.any(
        (s) => s.playerId == widget.playerId && s.isHost,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DehlaLobbyScreen(
            api: widget.api,
            room: room,
            playerId: widget.playerId,
            isHost: isHost,
            nickname: widget.nickname,
          ),
        ),
      );
    } catch (_) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _hostEndGame() async {
    final code = widget.roomCode;
    if (code == null || _hostBusy) return;
    final ok = await showEndGameDialog(context);
    if (!ok || !mounted) return;
    setState(() => _hostBusy = true);
    try {
      await widget.api.endGame(code);
      // WS GameEnded also navigates; this covers REST-only confirmation.
      await _returnToLobby();
    } catch (e) {
      if (mounted) setState(() => _reject = '$e');
    } finally {
      if (mounted) setState(() => _hostBusy = false);
    }
  }

  Future<void> _hostRestart() async {
    final code = widget.roomCode;
    if (code == null || _hostBusy) return;
    setState(() => _hostBusy = true);
    try {
      final result = await widget.api.restartGame(code);
      if (result.gameId != null && mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DehlaTableScreen(
              api: widget.api,
              gameId: result.gameId!,
              playerId: widget.playerId,
              roomCode: code,
              isHost: widget.isHost,
              nickname: widget.nickname,
            ),
          ),
        );
      } else {
        await _returnToLobby();
      }
    } catch (e) {
      if (mounted) setState(() => _reject = '$e');
    } finally {
      if (mounted) setState(() => _hostBusy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showLeaveTableDialog(context);
    if (!ok || !mounted) return;
    trackDehlaEvent('exit_table');
    final code = widget.roomCode;
    if (code != null) {
      try {
        await widget.api.leaveRoom(code);
      } catch (_) {}
      // Keep reclaim blob so the same nick can reclaim the vacant seat.
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Seat index relative to viewer for arc layout: 0=self bottom, then anticlockwise.
  Alignment _alignmentForRelative(int rel) {
    switch (rel % 4) {
      case 0:
        return const Alignment(0, 0.92);
      case 1:
        return const Alignment(-0.85, 0);
      case 2:
        return const Alignment(0, -0.88);
      default:
        return const Alignment(0.85, 0);
    }
  }

  String? get _vacantNickname {
    final v = _view;
    if (v == null) return null;
    for (final o in v.opponents) {
      if (o.vacant) return o.nickname;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _leave();
      },
      child: Scaffold(
        backgroundColor: feltGreenDark,
        body: SafeArea(
          child: v == null
              ? const Center(
                  child: CircularProgressIndicator(color: goldAccent),
                )
              : Column(
                  children: [
                    _TopBar(view: v, onLeave: _leave),
                    if (v.paused)
                      _PauseBanner(
                        vacantName: _vacantNickname,
                        roomCode: widget.roomCode,
                        isHost: widget.isHost,
                        hostBusy: _hostBusy,
                        onRestart: widget.isHost ? _hostRestart : null,
                        onEndGame: widget.isHost ? _hostEndGame : null,
                      ),
                    if (_reject != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _reject!,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    if (v.phase == 'hand_complete')
                      _PhaseBanner(
                        message: v.handWinner == null
                            ? 'Hand complete'
                            : '${teamSideLabel(v.handWinner)} side takes the Kot · '
                                  '${v.kotsA}–${v.kotsB}',
                        accent: teamRingFor(v.handWinner),
                        actionLabel: v.canStartNextHand ? t('next_hand') : null,
                        onAction: v.canStartNextHand
                            ? () => _socket?.startNextHand(
                                v.gameId,
                                v.stateVersion,
                              )
                            : null,
                      ),
                    if (v.phase == 'match_complete')
                      _PhaseBanner(
                        message: v.matchWinner == null
                            ? 'Match complete'
                            : '${teamSideLabel(v.matchWinner)} side wins the match!',
                        accent: teamRingFor(v.matchWinner),
                        actionLabel: v.canRematch ? t('rematch') : null,
                        onAction: v.canRematch
                            ? () => _socket?.rematch(v.gameId, v.stateVersion)
                            : null,
                        secondaryLabel: 'Home',
                        onSecondary: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    Expanded(child: _buildFelt(v)),
                    if (v.canAnnounceTrump && !v.paused)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final suit in [
                              'spades',
                              'hearts',
                              'diamonds',
                              'clubs',
                            ])
                              FilledButton(
                                onPressed: () => _socket?.announceTrump(
                                  v.gameId,
                                  v.stateVersion,
                                  suit,
                                ),
                                child: Text(
                                  suitSymbols[suit] ?? suit,
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: suitColor(suit),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (!v.paused &&
                        v.phase != 'hand_complete' &&
                        v.phase != 'match_complete')
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          v.turnSeat == v.ownSeat
                              ? t('your_turn')
                              : t('waiting_turn').replaceAll(
                                  '{name}',
                                  v.nicknameForSeat(v.turnSeat ?? -1) ?? '…',
                                ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    _HandStrip(
                      view: v,
                      isPlayable: _isPlayable,
                      onPlay: (c) =>
                          _socket?.playCard(v.gameId, v.stateVersion, c),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFelt(PlayerGameView v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: AspectRatio(
        aspectRatio: 1.15,
        child: Container(
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              colors: [Color(0xFF2E7D32), feltGreen, feltGreenDark],
              radius: 0.95,
            ),
            borderRadius: BorderRadius.circular(160),
            border: Border.all(color: const Color(0xFF5D4037), width: 6),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              for (var seat = 0; seat < 4; seat++)
                Align(
                  alignment: _alignmentForRelative((seat - v.ownSeat + 4) % 4),
                  child: _SeatChip(
                    seat: seat,
                    view: v,
                    isTurn: v.turnSeat == seat && !v.paused,
                  ),
                ),
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PileHud(
                      pileCount: v.centrePileCount,
                      lastWinnerName: v.lastTrickWinnerSeat == null
                          ? null
                          : v.nicknameForSeat(v.lastTrickWinnerSeat!),
                      oneAwayName: v.oneAwaySeat == null
                          ? null
                          : v.nicknameForSeat(v.oneAwaySeat!),
                      trump: v.trump,
                      tricksPlayed: v.tricksPlayed,
                    ),
                    if (v.currentTrick.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final t in v.currentTrick)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PlayingCardWidget(card: t.card, width: 44),
                                const SizedBox(height: 2),
                                Text(
                                  v.nicknameForSeat(t.seat) ?? 'Seat ${t.seat}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.view, required this.onLeave});
  final PlayerGameView view;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              view.trump == null
                  ? 'Trump —'
                  : '${suitSymbols[view.trump]} trump',
              style: TextStyle(
                color: feltGreenDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TeamScoreStrip(
            kotsA: view.kotsA,
            kotsB: view.kotsB,
            tensA: view.tensA,
            tensB: view.tensB,
          ),
          const Spacer(),
          IconButton(
            onPressed: onLeave,
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Leave',
          ),
        ],
      ),
    );
  }
}

/// Soft slate/teal pause chrome — matches Judgement table pause banner.
class _PauseBanner extends StatelessWidget {
  const _PauseBanner({
    this.vacantName,
    this.roomCode,
    this.isHost = false,
    this.hostBusy = false,
    this.onRestart,
    this.onEndGame,
  });

  final String? vacantName;
  final String? roomCode;
  final bool isHost;
  final bool hostBusy;
  final VoidCallback? onRestart;
  final VoidCallback? onEndGame;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF243B3A);
    const accent = Color(0xFF7EB8B2);
    const border = Color(0xFF3A5C58);
    final vacant = vacantName != null;

    return Container(
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
                  vacant ? t('seat_open') : t('table_paused'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vacant
                      ? '${vacantName!} left — share the join link so they (or a friend) can reclaim. '
                            '${isHost ? 'As host you can restart (lobby) or end the game.' : 'Waiting for host or a rejoin.'}'
                      : 'Waiting for a player to reconnect…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                if (roomCode != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            showDehlaInviteSheet(context, code: roomCode!),
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: const Text('Invite'),
                        style: FilledButton.styleFrom(
                          foregroundColor: accent,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final url = dehlaRoomInviteUrl(code: roomCode!);
                          await Clipboard.setData(ClipboardData(text: url));
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
                        label: const Text('Copy link'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.55),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (isHost && vacant && onRestart != null)
                        FilledButton(
                          onPressed: hostBusy ? null : onRestart,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: const Color(0xFF0E1F1E),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(hostBusy ? 'Restarting…' : 'Restart'),
                        ),
                      if (isHost && onEndGame != null)
                        TextButton(
                          onPressed: hostBusy ? null : onEndGame,
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
    );
  }
}

class _TeamScoreStrip extends StatelessWidget {
  const _TeamScoreStrip({
    required this.kotsA,
    required this.kotsB,
    required this.tensA,
    required this.tensB,
  });

  final int kotsA;
  final int kotsB;
  final int tensA;
  final int tensB;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Kot ',
          style: TextStyle(
            color: goldAccent,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        _TeamPip(color: teamRingWarm),
        const SizedBox(width: 4),
        Text(
          '$kotsA–$kotsB',
          style: const TextStyle(
            color: goldAccent,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 4),
        _TeamPip(color: teamRingCool),
        const SizedBox(width: 8),
        Text(
          'Tens $tensA–$tensB',
          style: TextStyle(
            color: goldAccent.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _TeamPip extends StatelessWidget {
  const _TeamPip({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({
    required this.message,
    this.accent,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final Color? accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: goldAccent.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black38),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black87,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(secondaryLabel!),
              ),
            ],
            if (actionLabel != null && onAction != null)
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: feltGreenDark,
                  foregroundColor: goldAccent,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeatChip extends StatelessWidget {
  const _SeatChip({
    required this.seat,
    required this.view,
    required this.isTurn,
  });

  final int seat;
  final PlayerGameView view;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    final isSelf = seat == view.ownSeat;
    String name;
    String? avatarId;
    String? team;
    var vacant = false;
    if (isSelf) {
      name = 'You';
      team = view.ownTeam;
      avatarId = view.ownAvatarId;
    } else {
      OpponentView? o;
      for (final x in view.opponents) {
        if (x.seat == seat) o = x;
      }
      name = o?.nickname ?? 'Seat $seat';
      team = o?.team;
      avatarId = o?.avatarId;
      vacant = o?.vacant ?? false;
    }
    final dealer = seat == view.dealerSeat;
    final ring = vacant ? null : teamRingFor(team);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            PlayerAvatar(
              avatarId: avatarId,
              nickname: name,
              radius: 22,
              highlight: isTurn,
              muted: vacant,
              teamRing: ring,
            ),
            if (dealer && !vacant)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: goldAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: feltGreenDark, width: 1.5),
                  ),
                  child: const Text(
                    'D',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ring != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: ring,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                vacant ? '$name · open' : name,
                style: TextStyle(
                  color: isTurn ? goldAccent : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HandStrip extends StatelessWidget {
  const _HandStrip({
    required this.view,
    required this.isPlayable,
    required this.onPlay,
  });

  final PlayerGameView view;
  final bool Function(CardModel) isPlayable;
  final ValueChanged<CardModel> onPlay;

  @override
  Widget build(BuildContext context) {
    final myTurn = view.turnSeat == view.ownSeat && !view.paused;
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final c in view.ownHand)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: PlayingCardWidget(
                card: c,
                width: 58,
                highlighted: isPlayable(c) && myTurn,
                disabled: !isPlayable(c) || !myTurn,
                onTap: isPlayable(c) && myTurn ? () => onPlay(c) : null,
              ),
            ),
        ],
      ),
    );
  }
}
