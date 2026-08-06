import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/protocol.dart';

/// Presets + reorder for a 4-suit trump cycle.
class TrumpCycleEditor extends StatelessWidget {
  final List<String> cycle;
  final ValueChanged<List<String>> onChanged;

  const TrumpCycleEditor({
    super.key,
    required this.cycle,
    required this.onChanged,
  });

  static const presets = <String, List<String>>{
    'Classic ♠♦♣♥': classicTrumpCycle,
    '♠♣♥♦': ['spades', 'clubs', 'hearts', 'diamonds'],
    '♥♦♠♣': ['hearts', 'diamonds', 'spades', 'clubs'],
    '♦♣♥♠': ['diamonds', 'clubs', 'hearts', 'spades'],
  };

  static String _suitLabel(String suit) {
    if (suit.isEmpty) return suit;
    return '${suit[0].toUpperCase()}${suit.substring(1)}';
  }

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= cycle.length) return;
    final next = List<String>.from(cycle);
    final tmp = next[from];
    next[from] = next[to];
    next[to] = tmp;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in presets.entries)
              ChoiceChip(
                label: Text(entry.key, style: const TextStyle(fontSize: 12)),
                selected: listEquals(cycle, entry.value),
                onSelected: (_) => onChanged(List<String>.from(entry.value)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < cycle.length; i++) ...[
              if (i > 0)
                const Text('→', style: TextStyle(color: Colors.white54)),
              Text(
                suitSymbols[cycle[i]] ?? '?',
                style: TextStyle(
                  fontSize: 20,
                  color: suitColor(cycle[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < cycle.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    suitSymbols[cycle[i]] ?? '?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      color: suitColor(cycle[i]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _suitLabel(cycle[i]),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                _MoveButton(
                  label: '▲',
                  enabled: i > 0,
                  onPressed: () => _move(i, -1),
                ),
                _MoveButton(
                  label: '▼',
                  enabled: i < cycle.length - 1,
                  onPressed: () => _move(i, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Explicit light glyphs — Material Icons can be invisible on felt green /
/// web tree-shaken icon fonts.
class _MoveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _MoveButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              height: 1,
              color: enabled ? Colors.white70 : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
