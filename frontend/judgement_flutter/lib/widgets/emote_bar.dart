import 'dart:async';

import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../util/emote_lexicon.dart';
import '../util/soundboard.dart';
import '../util/table_audio.dart';
import 'cartoon_text_blast.dart';

/// Quick reacts + soundboard + short vibe text + tap-to-talk voice.
class EmoteBar extends StatefulWidget {
  final GameController controller;

  const EmoteBar({super.key, required this.controller});

  @override
  State<EmoteBar> createState() => _EmoteBarState();
}

class _EmoteBarState extends State<EmoteBar> {
  final _text = TextEditingController();
  final _recorder = VoiceRecorder();
  var _expanded = false;
  var _soundsOpen = false;
  var _recording = false;
  var _busy = false;
  DateTime? _recordStarted;
  Timer? _recordTicker;
  String? _localHint;

  @override
  void dispose() {
    _recordTicker?.cancel();
    unawaited(_recorder.dispose());
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text;
    final style = resolveEmoteText(typed);
    final elapsed = _recordStarted == null
        ? 0
        : DateTime.now().difference(_recordStarted!).inMilliseconds;
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
                  tooltip: 'Soundboard',
                  onPressed: () {
                    unawaited(widget.controller.audio.unlock());
                    setState(() {
                      _soundsOpen = !_soundsOpen;
                      if (_soundsOpen) _expanded = false;
                    });
                  },
                  icon: Icon(
                    _soundsOpen ? Icons.music_off : Icons.music_note,
                    size: 18,
                    color: Colors.lightBlueAccent,
                  ),
                ),
                IconButton(
                  tooltip: _recording
                      ? 'Tap to send (${(elapsed / 1000).toStringAsFixed(1)}s)'
                      : 'Tap to record voice (max 6s)',
                  onPressed: _busy ? null : () => unawaited(_toggleRecord()),
                  icon: Icon(
                    _recording ? Icons.stop_circle : Icons.mic_none,
                    size: 18,
                    color: _recording ? Colors.redAccent : Colors.white70,
                  ),
                ),
                IconButton(
                  tooltip: 'Type a vibe',
                  onPressed: () => setState(() {
                    _expanded = !_expanded;
                    if (_expanded) _soundsOpen = false;
                  }),
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
                IconButton(
                  tooltip: widget.controller.muteReactions
                      ? 'Unmute table noise'
                      : 'Mute table noise',
                  onPressed: () {
                    final next = !widget.controller.muteReactions;
                    widget.controller.setMuteTableNoise(next);
                    if (!next) {
                      unawaited(widget.controller.audio.unlock());
                    }
                  },
                  icon: Icon(
                    widget.controller.muteReactions
                        ? Icons.volume_off
                        : Icons.volume_up,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          if (widget.controller.audio.awaitingUnlock)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.amber.withValues(alpha: 0.15),
                ),
                onPressed: () async {
                  // Await unlock so the first clip plays inside this gesture.
                  await widget.controller.audio.unlock();
                  widget.controller.audioQueueFullHint = null;
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.volume_up, size: 16, color: Colors.amberAccent),
                label: const Text(
                  'Tap to enable table sound',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ),
            ),
          if (_localHint != null || widget.controller.audioQueueFullHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _localHint ?? widget.controller.audioQueueFullHint!,
                style: TextStyle(
                  color: Colors.orangeAccent.withValues(alpha: 0.9),
                  fontSize: 11,
                ),
              ),
            ),
          if (_soundsOpen)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final clip in soundboardClips)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: Text(clip.emoji, style: const TextStyle(fontSize: 14)),
                        label: Text(clip.label, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.black38,
                        labelStyle: const TextStyle(color: Colors.white),
                        onPressed: () {
                          unawaited(widget.controller.audio.unlock());
                          widget.controller.sendSoundboard(clip.id);
                          setState(() => _localHint = null);
                        },
                      ),
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

  Future<void> _toggleRecord() async {
    if (_busy) return;
    if (_recording) {
      await _finishRecord();
    } else {
      await _beginRecord();
    }
  }

  Future<void> _beginRecord() async {
    // Do not setState/await anything before start() — prod Chrome drops the
    // user gesture and getUserMedia then fails (localhost is more lenient).
    _busy = true;
    _localHint = null;
    widget.controller.audioQueueFullHint = null;
    try {
      await _recorder.start();
      _recordStarted = DateTime.now();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _busy = false;
        _localHint = 'Recording… tap mic again to send';
      });
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final ms = DateTime.now().difference(_recordStarted!).inMilliseconds;
        if (ms >= maxVoiceDurationMs) {
          unawaited(_finishRecord());
        } else {
          setState(() {});
        }
      });
      unawaited(widget.controller.audio.unlock());
    } catch (error) {
      final msg = error.toString().toLowerCase();
      final denied = msg.contains('permission') ||
          msg.contains('notallowed') ||
          msg.contains('denied') ||
          msg.contains('notallowederror');
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = false;
          _localHint = denied
              ? 'Allow microphone in the site lock icon, then tap mic again'
              : 'Mic blocked — Chrome/Edge, HTTPS, allow mic for this site';
        });
      }
    }
  }

  Future<void> _finishRecord() async {
    if (!_recording || _busy) return;
    _recordTicker?.cancel();
    setState(() {
      _busy = true;
      _recording = false;
    });
    try {
      final note = await _recorder.stop();
      _recordStarted = null;
      if (note == null) {
        setState(() {
          _busy = false;
          _localHint = 'Speak ~1s+ (Chrome/Edge; Opus required)';
        });
        return;
      }
      await widget.controller.sendVoiceNote(
        mime: note.mime,
        durationMs: note.durationMs,
        audioB64: note.audioB64,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _localHint = null;
        });
      }
    } catch (_) {
      _recordStarted = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _localHint = 'Could not send voice note';
        });
      }
    }
  }
}
