import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../util/table_media_session.dart';
import 'lobby_screen.dart';

/// Public RSVP page for `/e/{slug}` (ADR 0005).
class EventInviteScreen extends StatefulWidget {
  final String slug;

  const EventInviteScreen({super.key, required this.slug});

  @override
  State<EventInviteScreen> createState() => _EventInviteScreenState();
}

class _EventInviteScreenState extends State<EventInviteScreen> {
  final _api = ApiClient();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  GameEventPublicView? _event;
  String? _error;
  String? _rsvpToken;
  String? _rsvpStatus;
  int? _waitlistPosition;
  bool _consent = true;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final event = await _api.getEvent(widget.slug);
      if (mounted) setState(() => _event = event);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load event');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rsvp() async {
    final name = _name.text.trim();
    final mobile = _mobile.text.trim();
    if (name.isEmpty || mobile.isEmpty) {
      _toast('Enter your name and mobile number');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _api.createRsvp(
        widget.slug,
        displayName: name,
        mobile: mobile,
        contactConsent: _consent,
      );
      if (!mounted) return;
      setState(() {
        _event = result.event;
        _rsvpToken = result.rsvpToken;
        _rsvpStatus = result.rsvpStatus;
        _waitlistPosition = result.waitlistPosition;
      });
      _toast(result.rsvpStatus == 'waitlisted'
          ? 'You’re on the waitlist (#${result.waitlistPosition})'
          : 'You’re in — add this to your calendar');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addToCalendar() async {
    final url = Uri.parse(_api.calendarIcsUrl(widget.slug));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _toast('Could not open calendar download');
    }
  }

  Future<void> _joinLobby() async {
    final code = _event?.roomCode;
    if (code == null) return;
    final nickname = _name.text.trim().isEmpty ? 'Player' : _name.text.trim();
    setState(() => _busy = true);
    try {
      await TableMediaSession.prepareBeforeNetwork();
      final session = await _api.createGuestSession(nickname);
      final joined = await _api.joinRoom(code);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LobbyScreen(
          api: _api,
          nickname: session.nickname,
          initialRoom: joined.room,
          myPlayerId: joined.playerId,
        ),
      ));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game invite'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Text(_error!, textAlign: TextAlign.center)
                    : _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final event = _event!;
    final local = event.startsAt.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(event.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '${local.year}-${local.month.toString().padLeft(2, '0')}-'
              '${local.day.toString().padLeft(2, '0')} '
              '${local.hour.toString().padLeft(2, '0')}:'
              '${local.minute.toString().padLeft(2, '0')} '
              '(${event.timezone})',
            ),
            Text('Host: ${event.hostNickname}'),
            Text(
              '${event.goingCount} / ${event.maxPlayers} going '
              '(${event.seatsLeft} seats left)',
            ),
            Text(
              'Waitlist ${event.waitlistedCount} / 5 '
              '(${event.waitlistLeft} left)',
            ),
            if (event.goingNames.isNotEmpty)
              Text('Going: ${event.goingNames.join(', ')}',
                  style: const TextStyle(color: Colors.white54)),
            if (event.waitlistedNames.isNotEmpty)
              Text('Waitlist: ${event.waitlistedNames.join(', ')}',
                  style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _addToCalendar,
              icon: const Icon(Icons.calendar_month),
              label: const Text('Add to calendar'),
            ),
            if (event.status == 'lobby_open' && event.roomCode != null) ...[
              const SizedBox(height: 12),
              Text('Lobby open — code ${event.roomCode}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_rsvpStatus == 'going' || _rsvpStatus == null)
                FilledButton(
                  onPressed: _busy ? null : _joinLobby,
                  child: const Text('Join lobby'),
                )
              else
                const Text(
                  'Waitlisted guests join only if promoted into a seat.',
                  style: TextStyle(color: Colors.white54),
                ),
            ],
            if (event.status == 'open' && _rsvpToken == null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile',
                  hintText: '10-digit or +91…',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'Contact me about this game',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              FilledButton(
                onPressed: _busy || !event.canRsvp ? null : _rsvp,
                child: Text(!event.canRsvp
                    ? 'Full'
                    : event.seatsLeft > 0
                        ? 'I am interested'
                        : 'Join waitlist'),
              ),
            ],
            if (_rsvpToken != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _rsvpStatus == 'waitlisted'
                      ? 'You’re on the waitlist (#$_waitlistPosition). '
                          'Keep the calendar invite handy.'
                      : 'You’re in. Keep the calendar invite handy.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
