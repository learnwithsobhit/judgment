import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../networking/api_client.dart';

/// Post-game coaching + highlights loaded from verified analytics.
class CoachingPanel extends StatefulWidget {
  final ApiClient api;
  final String gameId;
  final String playerId;
  final String Function(String playerId) nicknameOf;

  const CoachingPanel({
    super.key,
    required this.api,
    required this.gameId,
    required this.playerId,
    required this.nicknameOf,
  });

  @override
  State<CoachingPanel> createState() => _CoachingPanelState();
}

class _CoachingPanelState extends State<CoachingPanel> {
  CoachingResponse? _coach;
  HighlightsResponse? _highlights;
  String? _error;
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
      final results = await Future.wait([
        widget.api.getCoach(widget.gameId, widget.playerId),
        widget.api.getHighlights(widget.gameId),
      ]);
      if (!mounted) return;
      setState(() {
        _coach = results[0] as CoachingResponse;
        _highlights = results[1] as HighlightsResponse;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Coaching unavailable. Your final scores above are still correct.';
        _loading = false;
      });
    }
  }

  String _humanize(String line) {
    // Replace raw player UUIDs in highlight lines with nicknames when possible.
    var out = line;
    final coach = _coach;
    if (coach != null) {
      out = out.replaceAll(coach.playerId, widget.nicknameOf(coach.playerId));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB4A8))),
      );
    }

    final coach = _coach!;
    final highlights = _highlights!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(coach.headline, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(coach.overall),
        if (coach.strongestRound != null) ...[
          const SizedBox(height: 8),
          Text(coach.strongestRound!),
        ],
        if (coach.weakestRound != null) ...[
          const SizedBox(height: 4),
          Text(coach.weakestRound!),
        ],
        const SizedBox(height: 8),
        Text(coach.riskPattern),
        const SizedBox(height: 12),
        const Text('Improvements', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final tip in coach.improvements)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(child: Text(tip)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(coach.positive, style: TextStyle(color: Colors.tealAccent.shade100)),
        if (coach.evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Evidence', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final e in coach.evidence.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
            ),
        ],
        const SizedBox(height: 20),
        const Text('Game highlights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        for (final line in highlights.lines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_humanize(line)),
          ),
        if (coach.fallbackReason != null || highlights.fallbackReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Shown from deterministic analytics (AI narration unavailable).',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
      ],
    );
  }
}
