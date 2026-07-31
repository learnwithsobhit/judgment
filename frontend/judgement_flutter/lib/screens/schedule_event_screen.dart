import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';
import 'event_manage_screen.dart';

/// Host creates a future meetup (ADR 0005).
class ScheduleEventScreen extends StatefulWidget {
  const ScheduleEventScreen({super.key});

  @override
  State<ScheduleEventScreen> createState() => _ScheduleEventScreenState();
}

class _ScheduleEventScreenState extends State<ScheduleEventScreen> {
  final _nickname = TextEditingController();
  final _title = TextEditingController(text: 'Judgement night');
  DateTime _startsAt = DateTime.now().toUtc().add(const Duration(hours: 24));
  String _timezone = 'Asia/Kolkata';
  int _durationMinutes = 90;
  bool _timerEnabled = true;
  int _timerSeconds = 30;
  String? _firstTrump;
  bool _busy = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt.toLocal(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt.toLocal()),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
    });
  }

  Future<void> _submit() async {
    final nickname = _nickname.text.trim();
    final title = _title.text.trim();
    if (nickname.isEmpty) {
      _showError('Pick a nickname first');
      return;
    }
    if (title.isEmpty) {
      _showError('Give the event a title');
      return;
    }
    setState(() => _busy = true);
    final api = ApiClient();
    try {
      await api.createGuestSession(nickname);
      final created = await api.createEvent(
        title: title,
        startsAt: _startsAt,
        timezone: _timezone,
        durationMinutes: _durationMinutes,
        turnTimeoutSeconds: _timerEnabled ? _timerSeconds : null,
        firstTrump: _firstTrump,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => EventManageScreen(
          api: api,
          slug: created.event.slug,
          manageToken: created.manageToken,
          nickname: nickname,
        ),
      ));
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _nickname.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = _startsAt.toLocal();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule a game'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create a future meetup. Share the invite link on WhatsApp; '
                      'guests RSVP with name and mobile. Up to 8 players (first come); '
                      '5 more can waitlist. Lobby size follows who is going.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nickname,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        labelText: 'Your nickname',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Event title',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Starts'),
                      subtitle: Text(
                        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
                        '${local.day.toString().padLeft(2, '0')} '
                        '${local.hour.toString().padLeft(2, '0')}:'
                        '${local.minute.toString().padLeft(2, '0')} (local)',
                      ),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: _pickDateTime,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _timezone,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Asia/Kolkata',
                          child: Text('Asia/Kolkata'),
                        ),
                        DropdownMenuItem(
                          value: 'UTC',
                          child: Text('UTC'),
                        ),
                        DropdownMenuItem(
                          value: 'America/New_York',
                          child: Text('America/New_York'),
                        ),
                        DropdownMenuItem(
                          value: 'Europe/London',
                          child: Text('Europe/London'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _timezone = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Duration: $_durationMinutes min'),
                    Slider(
                      value: _durationMinutes.toDouble(),
                      min: 30,
                      max: 240,
                      divisions: 14,
                      label: '$_durationMinutes min',
                      onChanged: (v) =>
                          setState(() => _durationMinutes = v.round()),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Turn timer'),
                      value: _timerEnabled,
                      onChanged: (v) => setState(() => _timerEnabled = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create event'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
