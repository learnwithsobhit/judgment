import 'package:flutter/material.dart';

import '../app/app.dart';
import '../models/protocol.dart';
import '../networking/api_client.dart';
import '../state/game_controller.dart' show GameConnectionState;
import '../state/spectator_controller.dart';
import '../widgets/playing_card.dart';
import '../widgets/spectator_victory_celebration.dart';
import 'spectator_result_screen.dart';

/// Read-only audience table with engagement rail.
class SpectatorTableScreen extends StatefulWidget {
  final ApiClient api;
  final String gameId;
  final String roomCode;
  final String nickname;

  const SpectatorTableScreen({
    super.key,
    required this.api,
    required this.gameId,
    required this.roomCode,
    required this.nickname,
  });

  @override
  State<SpectatorTableScreen> createState() => _SpectatorTableScreenState();
}

class _SpectatorTableScreenState extends State<SpectatorTableScreen> {
  late final SpectatorController _ctrl;
  final _comment = TextEditingController();
  bool _showResults = false;

  static const _reactEmojis = ['🔥', '👏', '😂', '😮', '💪'];

  @override
  void initState() {
    super.initState();
    _ctrl = SpectatorController(
      api: widget.api,
      gameId: widget.gameId,
      roomCode: widget.roomCode,
      nickname: widget.nickname,
    )..addListener(_onChanged);
    _ctrl.connect();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_ctrl.closedReason != null && !_ctrl.gameFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ctrl.closedReason!)),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _ctrl.view;
    final finished =
        _ctrl.gameFinished && view != null && view.finalRanking != null;

    if (finished) {
      if (_showResults) {
        return SpectatorResultScreen(controller: _ctrl);
      }
      return SpectatorVictoryCelebration(
        controller: _ctrl,
        onViewResults: () => setState(() => _showResults = true),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: feltGreenDark,
        title: Text('Watching ${widget.roomCode}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                view == null ? '…' : '${view.viewerCount} watching',
                style: const TextStyle(color: goldAccent),
              ),
            ),
          ),
        ],
      ),
      body: view == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _ctrl.connection == GameConnectionState.connecting
                        ? 'Joining the gallery…'
                        : (_ctrl.lastError ?? 'Connecting…'),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: _table(view)),
                if (wide) SizedBox(width: 320, child: _rail(view)),
              ],
            ),
      bottomNavigationBar: (!wide && view != null)
          ? SafeArea(child: SizedBox(height: 280, child: _rail(view)))
          : null,
    );
  }

  Widget _table(SpectatorGameView view) {
    final trick = view.currentTrick.isNotEmpty
        ? view.currentTrick
        : (view.lastCompletedTrick?.plays ?? const <PlayedCard>[]);
    final crowd = _ctrl.crowdPrediction;
    return Column(
      children: [
        if (crowd != null && crowd.totalVoters > 0) _crowdStrip(view, crowd),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(view.phase)),
              if (view.round != null)
                Chip(
                  label: Text(
                    'R${view.round!.roundIndex + 1}/${view.round!.totalRounds} · ${view.round!.cardsPerPlayer} cards',
                  ),
                ),
              if (view.trump != null)
                Chip(label: Text('Trump ${suitSymbols[view.trump] ?? view.trump}')),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                colors: [Color(0xFF2E7D32), feltGreenDark],
              ),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: view.seats.map((s) {
                    final turn = view.currentTurn == s.playerId;
                    return InkWell(
                      onTap: () => _ctrl.setWinnerPrediction(s.playerId),
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: turn
                              ? goldAccent.withValues(alpha: 0.25)
                              : Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                          border: crowd?.myPick == s.playerId
                              ? Border.all(color: goldAccent, width: 2)
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(s.nickname,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              'bid ${s.bid ?? '—'} · won ${s.tricksWon}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: trick
                      .map((p) => PlayingCardWidget(card: p.card, width: 54))
                      .toList(),
                ),
                const Spacer(),
                if (_ctrl.lastError != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _ctrl.lastError!,
                      style: TextStyle(color: Colors.amber.shade200),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: view.scores.map((s) {
              final name = view.seats
                      .where((x) => x.playerId == s.playerId)
                      .map((x) => x.nickname)
                      .firstOrNull ??
                  'Player';
              return Chip(label: Text('$name · ${s.totalScore}'));
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _crowdStrip(SpectatorGameView view, CrowdPredictionView crowd) {
    final names = {for (final s in view.seats) s.playerId: s.nickname};
    final leader = crowd.tallies.isEmpty ? null : crowd.tallies.first;
    return Container(
      width: double.infinity,
      color: Colors.black26,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        crowd.locked
            ? 'Crowd pick locked${leader == null ? '' : ' — ${names[leader.playerId] ?? 'leader'} (${leader.count})'}'
            : 'Crowd pick · tap a seat to back them${leader == null ? '' : ' · leading ${names[leader.playerId]} (${leader.count}/${crowd.totalVoters})'}',
        style: const TextStyle(color: goldAccent),
      ),
    );
  }

  Widget _rail(SpectatorGameView view) {
    return Material(
      color: feltGreenDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Audience', style: TextStyle(color: goldAccent)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              children: _reactEmojis
                  .map((e) => ActionChip(
                        label: Text(e),
                        onPressed: () => _ctrl.sendReaction(e),
                      ))
                  .toList(),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _ctrl.comments.length,
              itemBuilder: (_, i) {
                final c = _ctrl.comments[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${c.nickname}: ${c.text}'),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _comment,
                    decoration: const InputDecoration(
                      hintText: 'Cheer…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      _ctrl.sendComment(v);
                      _comment.clear();
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _ctrl.sendComment(_comment.text);
                    _comment.clear();
                  },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
          if (view.seats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                _ctrl.crowdPrediction?.locked == true
                    ? 'Predictions locked — final round'
                    : 'Tap a player on the table to predict the winner',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
