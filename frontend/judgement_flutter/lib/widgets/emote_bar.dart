import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../util/emote_lexicon.dart';
import 'cartoon_text_blast.dart';

/// Quick reacts + short vibe text → cartoon text blast + emoji trail.
class EmoteBar extends StatefulWidget {
  final GameController controller;

  const EmoteBar({super.key, required this.controller});

  @override
  State<EmoteBar> createState() => _EmoteBarState();
}

class _EmoteBarState extends State<EmoteBar> {
  final _text = TextEditingController();
  var _expanded = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text;
    final style = resolveEmoteText(typed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.black.withValues(alpha: 0.25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final emoji in quickReactEmojis)
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.controller.sendReaction(emoji),
                    icon: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                IconButton(
                  tooltip: 'Type a vibe',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.keyboard_hide : Icons.chat_bubble_outline,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
                IconButton(
                  tooltip: 'Flash cheer',
                  onPressed: () => widget.controller.sendAvatarFlash('cheer'),
                  icon: const Icon(Icons.flash_on, size: 18, color: Colors.amberAccent),
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          maxLength: 40,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: 'ye mara / nice trump / gg…',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _sendText(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        style.emojis.join(' '),
                        style: const TextStyle(fontSize: 16),
                      ),
                      IconButton(
                        onPressed: _sendText,
                        icon: const Icon(Icons.send, size: 18, color: Colors.white70),
                      ),
                    ],
                  ),
                  if (typed.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: CartoonTextPreview(text: typed, style: style),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _sendText() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendEmoteText(text);
    _text.clear();
    setState(() {});
  }
}
