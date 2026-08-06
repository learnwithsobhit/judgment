import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../theme/dehla_theme.dart';
import '../util/room_share.dart';
import '../widgets/app_version_bar.dart';
import '../widgets/exit_confirm_dialogs.dart';
import '../widgets/player_avatar.dart';
import '../widgets/share_sheet.dart';
import 'table_screen.dart';

class DehlaLobbyScreen extends StatefulWidget {
  const DehlaLobbyScreen({
    super.key,
    required this.api,
    required this.room,
    required this.playerId,
    required this.isHost,
    this.nickname = '',
  });

  final DehlaApiClient api;
  final RoomView room;
  final String playerId;
  final bool isHost;
  final String nickname;

  @override
  State<DehlaLobbyScreen> createState() => _DehlaLobbyScreenState();
}

class _DehlaLobbyScreenState extends State<DehlaLobbyScreen> {
  late RoomView _room = widget.room;
  Timer? _poll;
  String? _error;
  bool _busy = false;

  /// Host choose-partners: selected teammate (sits opposite host).
  String? _chosenTeammateId;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final room = await widget.api.getRoom(_room.code);
      if (!mounted) return;
      setState(() => _room = room);
      if (room.phase == 'in_game' && room.gameId != null) {
        _poll?.cancel();
        if (!mounted) return;
        final nick = widget.nickname.isNotEmpty
            ? widget.nickname
            : room.seats
                  .where((s) => s.playerId == widget.playerId)
                  .map((s) => s.nickname)
                  .firstOrNull;
        if (nick != null && nick.isNotEmpty) {
          widget.api.persistReclaim(
            roomCode: room.code,
            playerId: widget.playerId,
            nickname: nick,
            gameId: room.gameId,
          );
        }
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DehlaTableScreen(
              api: widget.api,
              gameId: room.gameId!,
              playerId: widget.playerId,
              roomCode: room.code,
              isHost: widget.isHost,
              nickname: nick ?? widget.nickname,
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _ready(bool v) async {
    setState(() => _busy = true);
    try {
      final room = await widget.api.setReady(_room.code, v);
      setState(() => _room = room);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _randomPartners() async {
    setState(() {
      _busy = true;
      _chosenTeammateId = null;
      _error = null;
    });
    try {
      final room = await widget.api.setPartnership(
        _room.code,
        mode: 'random_opposite',
      );
      setState(() => _room = room);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _confirmChoosePartners() async {
    final me = widget.playerId;
    final mate = _chosenTeammateId;
    if (mate == null) {
      setState(() => _error = 'Tap a teammate to sit opposite you');
      return;
    }
    final others = _room.seats
        .map((s) => s.playerId)
        .where((id) => id != me && id != mate)
        .toList();
    if (others.length != 2) {
      setState(() => _error = 'Need exactly four players');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await widget.api.setPartnership(
        _room.code,
        mode: 'choose_partners',
        pairs: [
          [me, mate],
          [others[0], others[1]],
        ],
      );
      setState(() {
        _room = room;
        _chosenTeammateId = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final gameId = await widget.api.startGame(_room.code);
      if (!mounted) return;
      _poll?.cancel();
      final nick = widget.nickname.isNotEmpty
          ? widget.nickname
          : _room.seats
                .where((s) => s.playerId == widget.playerId)
                .map((s) => s.nickname)
                .firstOrNull;
      if (nick != null && nick.isNotEmpty) {
        widget.api.persistReclaim(
          roomCode: _room.code,
          playerId: widget.playerId,
          nickname: nick,
          gameId: gameId,
        );
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DehlaTableScreen(
            api: widget.api,
            gameId: gameId,
            playerId: widget.playerId,
            roomCode: _room.code,
            isHost: widget.isHost,
            nickname: nick ?? widget.nickname,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showLeaveLobbyDialog(context);
    if (!ok || !mounted) return;
    try {
      await widget.api.leaveRoom(_room.code);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  SeatView? _seatAt(int i) {
    for (final s in _room.seats) {
      if (s.seat == i) return s;
    }
    return null;
  }

  /// Confirmed team ring, or warm/teal preview while choosing a teammate.
  Color? _previewTeamRing({required SeatView? seat, required bool choosing}) {
    if (seat == null) return null;
    final confirmed = teamRingFor(seat.team);
    if (confirmed != null) return confirmed;
    final mate = _chosenTeammateId;
    if (!choosing || mate == null) return null;
    final id = seat.playerId;
    final withHost = id == widget.playerId || id == mate;
    return withHost ? teamRingWarm : teamRingCool;
  }

  @override
  Widget build(BuildContext context) {
    SeatView? me;
    for (final s in _room.seats) {
      if (s.playerId == widget.playerId) me = s;
    }
    final full = _room.seats.length >= 4;
    final partnersOk = _room.seats.every((s) => s.team != null);
    final allReady =
        _room.seats.length == 4 && _room.seats.every((s) => s.ready);
    // Host can always re-pick teams before start (including after auto-random).
    final choosing = full && widget.isHost;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Lobby'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          _room.code,
                          style: const TextStyle(
                            color: goldAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Share the link — friends only need a nickname',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => showDehlaInviteSheet(
                                context,
                                code: _room.code,
                              ),
                              icon: const Icon(Icons.ios_share, size: 18),
                              label: const Text('Invite friends'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final url = dehlaRoomInviteUrl(
                                  code: _room.code,
                                );
                                await Clipboard.setData(
                                  ClipboardData(text: url),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Join link copied'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Copy join link'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _room.code),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Code copied'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.tag, size: 18),
                              label: const Text('Copy code'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Players ${_room.seats.length}/4',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Dehla Classic · ${_room.trumpMethod.replaceAll('_', ' ')} · '
                          'first to ${_room.kotsToWin} Kot',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < 4; i++)
                          _SeatRow(
                            index: i,
                            seat: _seatAt(i),
                            youId: widget.playerId,
                            selectable:
                                choosing &&
                                _seatAt(i) != null &&
                                _seatAt(i)!.playerId != widget.playerId,
                            selected:
                                _chosenTeammateId != null &&
                                _seatAt(i)?.playerId == _chosenTeammateId,
                            previewTeamRing: _previewTeamRing(
                              seat: _seatAt(i),
                              choosing: choosing,
                            ),
                            onTap:
                                choosing &&
                                    _seatAt(i) != null &&
                                    _seatAt(i)!.playerId != widget.playerId
                                ? () => setState(
                                    () => _chosenTeammateId = _seatAt(
                                      i,
                                    )!.playerId,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                if (full && widget.isHost) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Partnership',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    partnersOk
                        ? 'Partners sit opposite — matching rings are teammates. You can reshuffle or choose again before start.'
                        : 'Opposite seats are partners. Shuffle randomly, or choose who sits opposite you.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _busy ? null : _randomPartners,
                          child: Text(
                            partnersOk ? 'Reshuffle' : 'Random partners',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy || _chosenTeammateId == null
                              ? null
                              : _confirmChoosePartners,
                          child: const Text('Confirm teams'),
                        ),
                      ),
                    ],
                  ),
                  if (_chosenTeammateId == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'To choose: tap the player who should be your teammate, then Confirm teams.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Teammate selected — remaining two form the other team.',
                        style: TextStyle(
                          color: goldAccent.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                if (full && !widget.isHost && !partnersOk)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Waiting for host to set partnerships…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                if (!full)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Waiting for at least 4 players…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                if (full && !allReady && widget.isHost && partnersOk)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Waiting for everyone to be ready…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy || me == null
                            ? null
                            : () => _ready(!(me?.ready ?? false)),
                        child: Text(me?.ready == true ? 'Not ready' : 'Ready'),
                      ),
                    ),
                    if (widget.isHost) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              (_busy || !full || !partnersOk || !allReady)
                              ? null
                              : _start,
                          child: const Text('Start game'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                const AppVersionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.index,
    required this.seat,
    required this.youId,
    this.selectable = false,
    this.selected = false,
    this.previewTeamRing,
    this.onTap,
  });

  final int index;
  final SeatView? seat;
  final String youId;
  final bool selectable;
  final bool selected;
  final Color? previewTeamRing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = seat == null;
    final ring = previewTeamRing;
    String subtitle;
    if (empty) {
      subtitle = 'Seat $index';
    } else if (ring != null) {
      subtitle = 'Seat $index · ${ring == teamRingWarm ? 'Warm' : 'Teal'} side';
    } else if (selectable) {
      subtitle = 'Seat $index · tap as teammate';
    } else {
      subtitle = 'Seat $index';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: selected
            ? goldAccent.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? goldAccent
                    : selectable
                    ? Colors.white24
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                if (empty)
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white12,
                    child: Icon(
                      Icons.chair_alt_outlined,
                      color: Colors.white38,
                    ),
                  )
                else
                  PlayerAvatar(
                    avatarId: seat!.avatarId,
                    nickname: seat!.nickname,
                    radius: 20,
                    highlight: selected,
                    teamRing: ring,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empty
                            ? 'Empty seat'
                            : '${seat!.nickname}${seat!.playerId == youId ? ' (you)' : ''}'
                                  '${seat!.isHost ? ' · host' : ''}',
                        style: TextStyle(
                          color: empty ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!empty)
                  Icon(
                    seat!.ready ? Icons.check_circle : Icons.hourglass_empty,
                    color: seat!.ready
                        ? Colors.lightGreenAccent
                        : Colors.white24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
