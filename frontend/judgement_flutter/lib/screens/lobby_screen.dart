import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../state/game_controller.dart';
import '../util/room_share.dart';
import '../util/social_share.dart';
import '../widgets/app_version_bar.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/player_avatar.dart';
import '../widgets/share_sheet.dart';
import 'table_screen.dart';

class LobbyScreen extends StatefulWidget {
  final ApiClient api;
  final String nickname;
  final RoomView initialRoom;
  final String myPlayerId;

  const LobbyScreen({
    super.key,
    required this.api,
    required this.nickname,
    required this.initialRoom,
    required this.myPlayerId,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late RoomView _room = widget.initialRoom;
  Timer? _poll;
  bool _busy = false;
  bool _navigatedToGame = false;
  String? _myAvatarId;

  @override
  void initState() {
    super.initState();
    _myAvatarId = _room.seats
        .where((s) => s.playerId == widget.myPlayerId)
        .map((s) => s.avatarId)
        .firstOrNull;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final room = await widget.api.getRoom(_room.roomId);
      if (!mounted) return;
      final stillSeated =
          room.seats.any((s) => s.playerId == widget.myPlayerId);
      if (!stillSeated && room.phase == 'lobby') {
        _poll?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You were removed from the lobby')),
        );
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _room = room;
        _myAvatarId = room.seats
                .where((s) => s.playerId == widget.myPlayerId)
                .map((s) => s.avatarId)
                .firstOrNull ??
            _myAvatarId;
      });
      if (room.phase == 'in_game' && room.gameId != null) {
        _enterGame(room.gameId!);
      }
    } catch (_) {
      // Transient polling errors are ignored; the next tick retries.
    }
  }

  Future<void> _removePlayer(SeatView seat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove player'),
        content: Text('Remove ${seat.nickname} from the lobby?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final room =
          await widget.api.removePlayer(_room.roomId, seat.playerId);
      if (mounted) setState(() => _room = room);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterGame(String gameId) {
    if (_navigatedToGame || !mounted) return;
    _navigatedToGame = true;
    _poll?.cancel();
    final controller = GameController(
      api: widget.api,
      gameId: gameId,
      myPlayerId: widget.myPlayerId,
      myNickname: widget.nickname,
    )
      ..roomCode = _room.code
      ..amHost = _amHost;
    controller.connect();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TableScreen(controller: controller),
    ));
  }

  bool get _amHost =>
      _room.seats.any((s) => s.playerId == widget.myPlayerId && s.isHost);

  bool get _amReady =>
      _room.seats.any((s) => s.playerId == widget.myPlayerId && s.ready);

  /// The game can start once at least `min_players` are seated and everyone
  /// seated is ready (ADR 0003) — the room does not have to be full.
  bool get _canStart =>
      _amHost &&
      _room.seats.length >= _room.minPlayers &&
      _room.seats.every((s) => s.ready);

  Future<void> _toggleReady() async {
    setState(() => _busy = true);
    try {
      final room = await widget.api.setReady(_room.roomId, !_amReady);
      if (mounted) setState(() => _room = room);
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar(String avatarId) async {
    setState(() {
      _busy = true;
      _myAvatarId = avatarId;
    });
    try {
      await widget.api.setAvatar(avatarId);
      await _refresh();
    } on ApiException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final gameId = await widget.api.startGame(_room.roomId);
      _enterGame(gameId);
    } on ApiException catch (error) {
      if (error.code == 'CAPACITY_FULL' || error.statusCode == 503) {
        _showCapacityFull(error.message);
      } else {
        _showError(error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    _poll?.cancel();
    try {
      await widget.api.leaveRoom(_room.roomId);
    } catch (_) {
      // Leaving an emptied room returns 404; either way we go back.
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCapacityFull(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tables are full'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Try again later'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filled = _room.seats.length;
    final total = _room.maxPlayers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Leave room',
          onPressed: _leave,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          _room.code,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                            color: goldAccent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Share the link — friends only need a nickname',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () {
                                final text = buildLobbyInviteText(_room.code);
                                final url = roomInviteUrl(
                                  _room.code,
                                  medium: 'whatsapp',
                                );
                                showSocialShareSheet(
                                  context: context,
                                  title: 'Invite friends',
                                  text: text,
                                  url: url,
                                  campaign: ShareCampaign.lobbyInvite,
                                );
                              },
                              icon: const Icon(Icons.ios_share, size: 18),
                              label: const Text('Invite friends'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final link = roomInviteUrl(_room.code);
                                Clipboard.setData(ClipboardData(text: link));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Join link copied')),
                                );
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Copy join link'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _room.code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Room code copied')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy code'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text('Players $filled / $total',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          [
                            _room.turnTimeoutSeconds == null
                                ? 'No turn timer'
                                : '${_room.turnTimeoutSeconds}s turn timer',
                            _room.firstTrump == null
                                ? 'revealed-card trump'
                                : 'trump rotates from ${suitSymbols[_room.firstTrump]}',
                            _room.roundScheduleSummary,
                            _room.dealerTotalRestriction
                                ? 'dealer bid restriction on'
                                : 'dealer may match total',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        const SizedBox(height: 8),
                        for (var seat = 0; seat < total; seat++)
                          _seatTile(seat),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Your avatar', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                AvatarPicker(
                  selectedId: _myAvatarId,
                  onSelected: _busy ? (_) {} : _pickAvatar,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _toggleReady,
                        icon: Icon(_amReady ? Icons.close : Icons.check),
                        label: Text(_amReady ? 'Not ready' : 'Ready'),
                      ),
                    ),
                    if (_amHost) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy || !_canStart ? null : _start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start game'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_amHost && !_canStart)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      filled < _room.minPlayers
                          ? 'Waiting for at least ${_room.minPlayers} players '
                              '(${_room.minPlayers - filled} more)…'
                          : 'Waiting for everyone to be ready…',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                const SizedBox(height: 20),
                const AppVersionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seatTile(int seatNumber) {
    final seat = _room.seats.where((s) => s.seat == seatNumber).firstOrNull;
    final isMe = seat?.playerId == widget.myPlayerId;
    final canRemove = _amHost && seat != null && !isMe && !_busy;
    return ListTile(
      dense: true,
      leading: seat == null
          ? const CircleAvatar(
              backgroundColor: Colors.white12,
              child: Icon(Icons.person_outline, size: 18, color: Colors.white38),
            )
          : PlayerAvatar(
              avatarId: seat.avatarId,
              nickname: seat.nickname,
              radius: 18,
              highlight: isMe,
            ),
      title: Text(seat == null
          ? 'Empty seat'
          : '${seat.nickname}${isMe ? ' (you)' : ''}${seat.isHost ? ' · host' : ''}'),
      trailing: seat == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRemove)
                  IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Remove from lobby',
                    onPressed: () => _removePlayer(seat),
                  ),
                seat.ready
                    ? const Icon(Icons.check_circle,
                        color: Colors.lightGreenAccent)
                    : const Icon(Icons.hourglass_empty, color: Colors.white38),
              ],
            ),
    );
  }
}
