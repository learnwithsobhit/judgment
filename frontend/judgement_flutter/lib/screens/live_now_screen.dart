import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../util/room_share.dart';
import 'spectator_table_screen.dart';

/// Browse public live tables + enter a watch code.
class LiveNowScreen extends StatefulWidget {
  final String? initialWatchCode;

  const LiveNowScreen({super.key, this.initialWatchCode});

  @override
  State<LiveNowScreen> createState() => _LiveNowScreenState();
}

class _LiveNowScreenState extends State<LiveNowScreen> {
  final _api = ApiClient();
  final _nickname = TextEditingController();
  final _code = TextEditingController();
  Timer? _poll;
  List<LiveRoomCard> _rooms = const [];
  bool _loading = true;
  bool _busy = false;
  bool _ensuringSession = false;
  String? _sessionNickname;
  String? _error;

  @override
  void initState() {
    super.initState();
    final code = widget.initialWatchCode;
    if (code != null) _code.text = code;
    _nickname.text = 'Fan';
    _bootstrap();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) _refresh();
    });
  }

  Future<void> _bootstrap() async {
    await _ensureGuestSession();
    await _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nickname.dispose();
    _code.dispose();
    super.dispose();
  }

  /// One guest session per Live Now visit; reuse across watch taps.
  Future<bool> _ensureGuestSession() async {
    final nick = _nickname.text.trim();
    if (nick.isEmpty) return false;
    if (_api.token != null && _sessionNickname == nick) return true;
    if (_ensuringSession) return _api.token != null;
    _ensuringSession = true;
    try {
      await _api.createGuestSession(nick);
      _sessionNickname = nick;
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _error = e.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _error = '$e');
      return false;
    } finally {
      _ensuringSession = false;
    }
  }

  Future<void> _refresh() async {
    try {
      final rooms = await _api.listLiveRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _watch(String code) async {
    final nick = _nickname.text.trim();
    if (nick.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a nickname to watch')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _ensureGuestSession();
      if (!ok) return;
      final watched =
          await _api.watchRoom(code.trim().toUpperCase(), nickname: nick);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SpectatorTableScreen(
          api: _api,
          gameId: watched.gameId,
          roomCode: watched.roomCode,
          nickname: nick,
        ),
      ));
      // Refresh catalog after returning from a watch.
      if (mounted) await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live now'),
        backgroundColor: feltGreenDark,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Watch public tables. Cheer — don’t play.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: goldAccent,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nickname,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Watch with code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final c = normalizeRoomCode(_code.text);
                  if (c != null) _watch(c);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        final c = normalizeRoomCode(_code.text);
                        if (c == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter a valid room code')),
                          );
                          return;
                        }
                        _watch(c);
                      },
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Watch table'),
              ),
              const SizedBox(height: 28),
              Text('Public tables', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(_error!, style: TextStyle(color: Colors.red.shade200))
              else if (_rooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No public tables right now. Enter a watch code above, or ask a host to list their game.',
                  ),
                )
              else
                ..._rooms.map((r) => Card(
                      child: ListTile(
                        title: Text('${r.hostNickname} · ${r.roomCode}'),
                        subtitle: Text(
                          '${r.playerCount}/${r.maxPlayers} playing · ${r.viewerCount} watching',
                        ),
                        trailing: const Icon(Icons.visibility),
                        onTap: _busy ? null : () => _watch(r.roomCode),
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
