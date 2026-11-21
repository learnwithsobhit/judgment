/// Compact emoji/mic/mute dock + bottom-sheet reaction picker.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../state/game_controller.dart';
import '../util/emote_lexicon.dart';
import '../util/soundboard.dart';
import '../util/table_audio.dart';
import 'cartoon_text_blast.dart';

const _dockGhostFill = Color(0x59000000); // black 35%
const _dockControlHeight = 40.0;
const _dockControlRadius = 8.0;

ButtonStyle _dockGhostStyle({Size minimumSize = const Size(40, 40)}) {
  return ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(_dockGhostFill),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    minimumSize: WidgetStatePropertyAll(minimumSize),
    maximumSize: WidgetStatePropertyAll(
      Size(double.infinity, minimumSize.height),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_dockControlRadius),
      ),
    ),
  );
}

/// Unlock strip shown above the dock while autoplay is blocked.
class EmoteUnlockBanner extends StatelessWidget {
  final GameController controller;

  const EmoteUnlockBanner({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.audio.awaitingUnlock) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () async {
                await controller.unlockTableAudio();
                controller.audioQueueFullHint = null;
              },
              icon: const Icon(
                Icons.volume_up,
                size: 16,
                color: Colors.amberAccent,
              ),
              label: const Text(
                'Enable sound',
                style: TextStyle(color: Colors.amberAccent, fontSize: 11),
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _dockIconButton({
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
}) {
  return IconButton(
    tooltip: tooltip,
    style: _dockGhostStyle(
      minimumSize: const Size(_dockControlHeight, _dockControlHeight),
    ),
    constraints: const BoxConstraints.tightFor(
      width: _dockControlHeight,
      height: _dockControlHeight,
    ),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: icon,
  );
}

/// Opens the emote sheet. Sits on the left of the dock caption row.
class EmoteReactButton extends StatelessWidget {
  final GameController controller;

  const EmoteReactButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return _dockIconButton(
      tooltip: 'Reactions',
      onPressed: () => showEmoteSheet(context, controller),
      icon: const Icon(
        Icons.emoji_emotions_outlined,
        size: 20,
        color: Colors.white70,
      ),
    );
  }
}

/// One-tap voice note on the dock. Tap to start, tap again to send (max 6s).
class EmoteMicButton extends StatefulWidget {
  final GameController controller;

  const EmoteMicButton({super.key, required this.controller});

  @override
  State<EmoteMicButton> createState() => _EmoteMicButtonState();
}

class _EmoteMicButtonState extends State<EmoteMicButton> {
  VoiceRecorder? _recorder;
  var _recording = false;
  var _busy = false;
  DateTime? _recordStarted;
  Timer? _recordTicker;

  @override
  void dispose() {
    _recordTicker?.cancel();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) unawaited(recorder.dispose());
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
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
    _busy = true;
    widget.controller.audioQueueFullHint = null;
    try {
      final recorder = _recorder ??= VoiceRecorder();
      await recorder.start();
      _recordStarted = DateTime.now();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _busy = false;
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
      unawaited(widget.controller.unlockTableAudio());
    } catch (error) {
      final msg = error.toString().toLowerCase();
      final denied =
          msg.contains('permission') ||
          msg.contains('notallowed') ||
          msg.contains('denied') ||
          msg.contains('notallowederror');
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = false;
        });
        _snack(
          denied
              ? 'Allow microphone in the site lock icon, then tap mic again'
              : 'Mic blocked — Chrome/Edge, HTTPS, allow mic for this site',
        );
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
      final note = await _recorder?.stop();
      _recordStarted = null;
      if (note == null) {
        if (mounted) {
          setState(() => _busy = false);
          _snack('Speak ~1s+ (Chrome/Edge; Opus required)');
        }
        return;
      }
      await widget.controller.sendVoiceNote(
        mime: note.mime,
        durationMs: note.durationMs,
        audioB64: note.audioB64,
      );
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      _recordStarted = null;
      if (mounted) {
        setState(() => _busy = false);
        _snack('Could not send voice note');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _recordStarted == null
        ? 0
        : DateTime.now().difference(_recordStarted!).inMilliseconds;
    return _dockIconButton(
      tooltip: _recording
          ? 'Tap to send (${(elapsed / 1000).toStringAsFixed(1)}s)'
          : 'Voice note',
      onPressed: _busy ? null : () => unawaited(_toggleRecord()),
      icon: Icon(
        _recording ? Icons.stop_circle : Icons.mic_none,
        size: 20,
        color: _recording ? Colors.redAccent : Colors.white70,
      ),
    );
  }
}

/// Mute toggle. Sits on the right of the dock caption row.
class EmoteMuteButton extends StatelessWidget {
  final GameController controller;

  const EmoteMuteButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return _dockIconButton(
          tooltip: controller.muteReactions
              ? 'Unmute table noise'
              : 'Mute table noise',
          onPressed: () {
            controller.setMuteTableNoise(!controller.muteReactions);
          },
          icon: Icon(
            controller.muteReactions ? Icons.volume_off : Icons.volume_up,
            size: 18,
            color: Colors.white70,
          ),
        );
      },
    );
  }
}

/// Leading dock controls kept for older call sites.
class EmoteBar extends StatelessWidget {
  final GameController controller;

  const EmoteBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return EmoteUnlockBanner(controller: controller);
  }
}

/// Full emote / soundboard / vibe / flash tools in a bottom sheet.
Future<void> showEmoteSheet(
  BuildContext context,
  GameController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: feltGreenDark,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _EmoteSheetBody(controller: controller),
      );
    },
  );
}

class _EmoteSheetBody extends StatefulWidget {
  final GameController controller;

  const _EmoteSheetBody({required this.controller});

  @override
  State<_EmoteSheetBody> createState() => _EmoteSheetBodyState();
}

class _EmoteSheetBodyState extends State<_EmoteSheetBody> {
  final _text = TextEditingController();
  var _expanded = false;
  var _soundsOpen = false;
  var _category = 0;
  String? _localHint;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text;
    final style = resolveEmoteText(typed);
    final category = reactionCategories[_category];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Table reacts',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < reactionCategories.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          reactionCategories[i].label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _category == i,
                        onSelected: (_) => setState(() => _category = i),
                        selectedColor: Colors.white24,
                        backgroundColor: Colors.black26,
                        labelStyle: const TextStyle(color: Colors.white),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        showCheckmark: false,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 168,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: category.emojis.length,
                itemBuilder: (context, index) {
                  final emoji = category.emojis[index];
                  return InkWell(
                    onTap: () {
                      widget.controller.sendReaction(emoji);
                      Navigator.of(context).maybePop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Soundboard',
                  onPressed: () {
                    unawaited(widget.controller.unlockTableAudio());
                    setState(() {
                      _soundsOpen = !_soundsOpen;
                      if (_soundsOpen) _expanded = false;
                    });
                  },
                  icon: Icon(
                    _soundsOpen ? Icons.music_off : Icons.music_note,
                    size: 20,
                    color: Colors.lightBlueAccent,
                  ),
                ),
                IconButton(
                  tooltip: 'Type a vibe',
                  onPressed: () => setState(() {
                    _expanded = !_expanded;
                    if (_expanded) _soundsOpen = false;
                  }),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_hide
                        : Icons.chat_bubble_outline,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
                IconButton(
                  tooltip: 'Flash cheer',
                  onPressed: () {
                    widget.controller.sendAvatarFlash('cheer');
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(
                    Icons.flash_on,
                    size: 20,
                    color: Colors.amberAccent,
                  ),
                ),
                IconButton(
                  tooltip: widget.controller.muteReactions
                      ? 'Unmute table noise'
                      : 'Mute table noise',
                  onPressed: () {
                    widget.controller.setMuteTableNoise(
                      !widget.controller.muteReactions,
                    );
                    setState(() {});
                  },
                  icon: Icon(
                    widget.controller.muteReactions
                        ? Icons.volume_off
                        : Icons.volume_up,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            if (_localHint != null ||
                widget.controller.audioQueueFullHint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _localHint ?? widget.controller.audioQueueFullHint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.orangeAccent.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ),
            if (_soundsOpen)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final clip in soundboardClips)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: Text(
                            clip.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                          label: Text(
                            clip.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.black38,
                          labelStyle: const TextStyle(color: Colors.white),
                          onPressed: () {
                            unawaited(
                              widget.controller.sendSoundboard(clip.id),
                            );
                            setState(() => _localHint = null);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                          icon: const Icon(
                            Icons.send,
                            size: 18,
                            color: Colors.white70,
                          ),
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
      ),
    );
  }

  void _sendText() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendEmoteText(text);
    _text.clear();
    setState(() {});
    Navigator.of(context).maybePop();
  }
}
