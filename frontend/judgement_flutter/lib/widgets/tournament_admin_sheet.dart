import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../networking/api_client.dart';
import '../theme/judgement_palette.dart';
import '../util/event_share.dart';
import 'player_avatar.dart';

typedef TournamentAdminListLoad = Future<List<TournamentSummary>> Function();

TournamentAdminListLoad tournamentAdminListLoad = () {
  final api = ApiClient()..token = AccountSession.instance.token;
  return api.adminListTournaments();
};

class TournamentAdminSheet extends StatefulWidget {
  const TournamentAdminSheet({super.key});

  @override
  State<TournamentAdminSheet> createState() => _TournamentAdminSheetState();
}

class _TournamentAdminSheetState extends State<TournamentAdminSheet> {
  late Future<List<TournamentSummary>> _load = tournamentAdminListLoad();
  final _title = TextEditingController();
  final _blurb = TextEditingController();
  DateTime _startsAt = _defaultStartsAt();
  bool _busy = false;

  static DateTime _defaultStartsAt() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 15) * 15);
  }

  @override
  void dispose() {
    _title.dispose();
    _blurb.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _load = tournamentAdminListLoad();
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _create({required bool goLive}) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give the event a title')));
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ApiClient()..token = AccountSession.instance.token;
      await api.createTournament(
        title: title,
        blurb: _blurb.text.trim(),
        status: goLive ? 'live' : 'draft',
        startsAt: _startsAt.toUtc(),
      );
      if (!mounted) return;
      _title.clear();
      _blurb.clear();
      setState(() => _startsAt = _defaultStartsAt());
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the tournament')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(TournamentSummary tournament, String status) async {
    setState(() => _busy = true);
    try {
      final api = ApiClient()..token = AccountSession.instance.token;
      await api.updateTournament(tournament.tournamentId, status: status);
      if (!mounted) return;
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the tournament')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TournamentSummary tournament) async {
    final label = tournamentDisplayLabel(tournament.title, tournament.startsAt);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          'Remove “$label” permanently? Old or test events can be cleaned up this way. Standings for this event go away; finished tables still count on Top players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final api = ApiClient()..token = AccountSession.instance.token;
      await api.deleteTournament(tournament.tournamentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $label')),
      );
      await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the tournament')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openManage(TournamentSummary tournament) async {
    setState(() => _busy = true);
    try {
      final api = ApiClient()..token = AccountSession.instance.token;
      final detail = await api.adminGetTournament(tournament.tournamentId);
      if (!mounted) return;
      // Clear busy before the peek sheet so Close / Go live stay tappable.
      setState(() => _busy = false);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _ManagePeek(
          detail: detail,
          onLive: () {
            Navigator.of(context).pop();
            _setStatus(detail.tournament, 'live');
          },
          onClose: () {
            Navigator.of(context).pop();
            _setStatus(detail.tournament, 'closed');
          },
          onReopen: () {
            Navigator.of(context).pop();
            _setStatus(detail.tournament, 'live');
          },
          onDelete: () {
            Navigator.of(context).pop();
            _delete(detail.tournament);
          },
        ),
      );
      if (mounted) await _reload();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load the tournament')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom > 0
        ? media.padding.bottom + 16
        : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tournaments', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Points series. Tables still count on Top players.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Friday night',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _blurb,
              enabled: !_busy,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Blurb (optional)',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts'),
              subtitle: Text(formatEventWhenLocal(_startsAt.toUtc())),
              trailing: const Icon(Icons.event),
              enabled: !_busy,
              onTap: _busy ? null : _pickDateTime,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _create(goLive: false),
                    child: const Text('Save draft'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _create(goLive: true),
                    child: Text(_busy ? 'Saving…' : 'Go live'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<TournamentSummary>>(
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('Could not load tournaments.');
                  }
                  final rows = snapshot.data ?? const <TournamentSummary>[];
                  if (rows.isEmpty) {
                    return const Text('No events yet. Create one above.');
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tournamentDisplayLabel(row.title, row.startsAt),
                        ),
                        subtitle: Text(
                          '${_statusLabel(row.status)} · '
                          '${row.finishedTables} finished'
                          '${row.liveAttachedRooms == null ? '' : ' · ${row.liveAttachedRooms} attached'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _openManage(row),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagePeek extends StatelessWidget {
  const _ManagePeek({
    required this.detail,
    required this.onLive,
    required this.onClose,
    required this.onReopen,
    required this.onDelete,
  });

  final TournamentDetail detail;
  final VoidCallback onLive;
  final VoidCallback onClose;
  final VoidCallback onReopen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = detail.tournament;
    final media = MediaQuery.of(context);
    final bottomPad = media.padding.bottom > 0
        ? media.padding.bottom + 16
        : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tournamentDisplayLabel(t.title, t.startsAt),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(_statusLabel(t.status)),
              visualDensity: VisualDensity.compact,
              backgroundColor: context.palette.feltDark.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${t.finishedTables} finished tables'
            '${t.liveAttachedRooms == null ? '' : ' · ${t.liveAttachedRooms} live attached'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('Standings peek', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (detail.players.isEmpty)
            const Text('Tables are still playing.')
          else
            for (final row in detail.players.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    PlayerAvatar(
                      avatarId: row.avatarId,
                      nickname: row.displayName,
                      photoUrl: row.photoUrl,
                      radius: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(row.displayName)),
                    Text('${row.medalPoints}'),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          if (t.isDraft)
            FilledButton(
              onPressed: onLive,
              child: const Text('Go live'),
            )
          else if (t.isLive)
            FilledButton(
              onPressed: onClose,
              child: const Text('Close event'),
            )
          else
            OutlinedButton(
              onPressed: onReopen,
              child: const Text('Reopen'),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onDelete,
            child: Text(
              'Delete event',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'live' => 'Live',
    'closed' => 'Closed',
    _ => 'Draft',
  };
}
