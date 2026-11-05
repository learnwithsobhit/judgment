import 'package:flutter/material.dart';

import '../app/app.dart';
import '../networking/api_client.dart';
import '../widgets/player_avatar.dart';

/// Post-game private ratings. Continues to results after submit or skip.
class FairPlayScreen extends StatefulWidget {
  const FairPlayScreen({
    super.key,
    required this.api,
    required this.gameId,
    required this.onContinue,
  });

  final ApiClient api;
  final String gameId;
  final VoidCallback onContinue;

  @override
  State<FairPlayScreen> createState() => _FairPlayScreenState();
}

class _FairPlayScreenState extends State<FairPlayScreen> {
  FairPlayGameView? _view;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _skipOnly = false;
  final Map<String, int> _scores = {};
  List<FairPlayTotal>? _totals;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final view = await widget.api.getFairPlay(widget.gameId);
      if (!mounted) return;
      if (view.alreadySubmitted && view.totals != null) {
        setState(() {
          _view = view;
          _totals = view.totals;
          _loading = false;
        });
        return;
      }
      if (view.canVote && view.ratees.isNotEmpty) {
        setState(() {
          _view = view;
          _loading = false;
        });
        return;
      }
      // Guest, solo signed-in table, or window closed — explain then continue.
      setState(() {
        _loading = false;
        _error = view.ratees.isEmpty
            ? 'Fair play needs at least one other signed-in player at the table.'
            : 'Fair play is not available for this seat.';
        _skipOnly = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      // Guests and non-roster seats skip quietly to results.
      if (error.statusCode == 401 || error.statusCode == 403) {
        widget.onContinue();
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
        _skipOnly = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load fair play.';
        _skipOnly = true;
      });
    }
  }

  bool get _allSet {
    final ratees = _view?.ratees ?? const [];
    return ratees.isNotEmpty && ratees.every((r) => _scores.containsKey(r.userId));
  }

  Future<void> _submit() async {
    if (!_allSet || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.api.submitFairPlay(
        widget.gameId,
        [
          for (final e in _scores.entries) (userId: e.key, points: e.value),
        ],
      );
      if (!mounted) return;
      setState(() {
        _totals = result.totals;
        _submitting = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Couldn\'t save fair play scores.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fair play'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [feltGreen, feltGreenDark],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _totals != null
              ? _TotalsPane(
                  totals: _totals!,
                  onContinue: widget.onContinue,
                )
              : _skipOnly
              ? _SkipPane(message: _error, onContinue: widget.onContinue)
              : _VotePane(
                  ratees: _view?.ratees ?? const [],
                  scores: _scores,
                  error: _error,
                  submitting: _submitting,
                  canSubmit: _allSet,
                  onScore: (userId, points) {
                    setState(() => _scores[userId] = points);
                  },
                  onSubmit: _submit,
                  onSkip: widget.onContinue,
                ),
        ),
      ),
    );
  }
}

class _SkipPane extends StatelessWidget {
  const _SkipPane({required this.message, required this.onContinue});

  final String? message;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message ?? 'Fair play is not available.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white,
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onContinue,
            child: const Text('View results'),
          ),
        ],
      ),
    );
  }
}

class _VotePane extends StatelessWidget {
  const _VotePane({
    required this.ratees,
    required this.scores,
    required this.error,
    required this.submitting,
    required this.canSubmit,
    required this.onScore,
    required this.onSubmit,
    required this.onSkip,
  });

  final List<FairPlayRatee> ratees;
  final Map<String, int> scores;
  final String? error;
  final bool submitting;
  final bool canSubmit;
  final void Function(String userId, int points) onScore;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rate how fairly each player competed. Scores are private — only totals are shown.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: ratees.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final ratee = ratees[index];
                return _RateeRow(
                  ratee: ratee,
                  selected: scores[ratee.userId],
                  onScore: (points) => onScore(ratee.userId, points),
                );
              },
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: canSubmit && !submitting ? onSubmit : null,
            child: Text(submitting ? 'Saving…' : 'Submit'),
          ),
          TextButton(
            onPressed: submitting ? null : onSkip,
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}

class _RateeRow extends StatelessWidget {
  const _RateeRow({
    required this.ratee,
    required this.selected,
    required this.onScore,
  });

  final FairPlayRatee ratee;
  final int? selected;
  final ValueChanged<int> onScore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PlayerAvatar(
              avatarId: ratee.avatarId,
              photoUrl: ratee.photoUrl,
              nickname: ratee.displayName,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ratee.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            Icon(
              Icons.handshake_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i <= 10; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: selected == i,
                onSelected: (_) => onScore(i),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

class _TotalsPane extends StatelessWidget {
  const _TotalsPane({required this.totals, required this.onContinue});

  final List<FairPlayTotal> totals;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This game\'s fair play totals',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Individual scores stay private.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: totals.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white12),
              itemBuilder: (context, index) {
                final row = totals[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PlayerAvatar(
                    avatarId: row.avatarId,
                    photoUrl: row.photoUrl,
                    nickname: row.displayName,
                    radius: 18,
                    signedIn: true,
                  ),
                  title: Text(
                    row.displayName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: Text(
                    '${row.points}',
                    style: const TextStyle(
                      color: goldAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                );
              },
            ),
          ),
          FilledButton(
            onPressed: onContinue,
            child: const Text('View results'),
          ),
        ],
      ),
    );
  }
}
