import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../util/event_share.dart';
import 'lobby_screen.dart';

/// Host manage page for a scheduled event (ADR 0005).
class EventManageScreen extends StatefulWidget {
  final ApiClient api;
  final String slug;
  final String manageToken;
  final String nickname;

  const EventManageScreen({
    super.key,
    required this.api,
    required this.slug,
    required this.manageToken,
    required this.nickname,
  });

  @override
  State<EventManageScreen> createState() => _EventManageScreenState();
}

class _EventManageScreenState extends State<EventManageScreen> {
  GameEventManageView? _view;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final view =
          await widget.api.manageEvent(widget.slug, widget.manageToken);
      if (mounted) setState(() => _view = view);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load manage view');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyShare() async {
    final event = _view?.event;
    if (event == null) return;
    // Compose on the client: server share_text uses PUBLIC_WEB_ORIGIN (often
    // :3000) and UTC clock labels that misread the event timezone.
    final text = eventShareText(event);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WhatsApp message copied')),
    );
  }

  Future<void> _openCalendar() async {
    final url = Uri.parse(widget.api.calendarIcsUrl(widget.slug));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openLobby() async {
    setState(() => _busy = true);
    try {
      if (widget.api.token == null) {
        await widget.api.createGuestSession(widget.nickname);
      }
      final result =
          await widget.api.openEventLobby(widget.slug, widget.manageToken);
      if (!mounted) return;
      if (result.capacity == 'busy') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lots of games are in progress right now. '
              'Starting may take a moment.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LobbyScreen(
          api: widget.api,
          nickname: widget.nickname,
          initialRoom: result.room,
          myPlayerId: result.playerId,
        ),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'CAPACITY_FULL' || e.statusCode == 503) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Tables are full'),
            content: Text(e.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await widget.api.cancelEvent(widget.slug, widget.manageToken);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteUrl = '${Uri.base.origin}/e/${widget.slug}';
    final manageUrl =
        '${Uri.base.origin}/e/${widget.slug}/manage?token=${widget.manageToken}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage event'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Text(_error!, textAlign: TextAlign.center)
                    : _buildBody(inviteUrl, manageUrl),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(String inviteUrl, String manageUrl) {
    final view = _view!;
    final event = view.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                Text('Status: ${event.status}'),
                Text(
                  '${event.goingCount}/${event.maxPlayers} going · '
                  '${event.waitlistedCount}/5 waitlist',
                ),
                if (event.goingCount < 3 && event.status == 'open')
                  const Text(
                    'Need at least 3 going RSVPs to open the lobby.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                if (event.roomCode != null)
                  Text('Room code: ${event.roomCode}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SelectableText('Invite: $inviteUrl'),
                const SizedBox(height: 4),
                SelectableText(
                  'Manage (keep private): $manageUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _copyShare,
              icon: const Icon(Icons.share),
              label: const Text('Copy WhatsApp text'),
            ),
            OutlinedButton.icon(
              onPressed: _openCalendar,
              icon: const Icon(Icons.calendar_month),
              label: const Text('Calendar .ics'),
            ),
            if (event.status == 'open')
              FilledButton.tonalIcon(
                onPressed:
                    _busy || event.goingCount < 3 ? null : _openLobby,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Open lobby'),
              ),
            if (event.status == 'open')
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel event'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Going', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _rsvpList(view.rsvps.where((r) => r.status == 'going').toList(),
            empty: 'No one confirmed yet'),
        const SizedBox(height: 16),
        Text('Waitlist', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _rsvpList(
          view.rsvps.where((r) => r.status == 'waitlisted').toList(),
          empty: 'Waitlist is empty',
        ),
      ],
    );
  }

  Widget _rsvpList(List<RsvpHostView> rsvps, {required String empty}) {
    if (rsvps.isEmpty) {
      return Text(empty, style: const TextStyle(color: Colors.white54));
    }
    return Card(
      child: Column(
        children: [
          for (final r in rsvps)
            ListTile(
              title: Text(r.displayName),
              subtitle: Text(r.mobileE164),
              trailing: r.contactConsent
                  ? const Icon(Icons.check_circle_outline, size: 18)
                  : null,
            ),
        ],
      ),
    );
  }
}
