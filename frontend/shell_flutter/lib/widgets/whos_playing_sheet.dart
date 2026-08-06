import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:judgement_flutter/util/avatar_pack.dart';
import 'package:judgement_flutter/widgets/avatar_picker.dart';

import '../profile/shell_profile.dart';
import '../theme/table_games_theme.dart';
import '../ux/copy.dart';

Future<ShellProfile?> showWhosPlayingSheet(
  BuildContext context, {
  ShellProfile? initial,
  String? title,
  String? body,
  bool clearNickname = false,
}) {
  return showModalBottomSheet<ShellProfile>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: feltGreenDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _WhosPlayingBody(
      initial: initial,
      title: title,
      body: body,
      clearNickname: clearNickname,
    ),
  );
}

class _WhosPlayingBody extends StatefulWidget {
  final ShellProfile? initial;
  final String? title;
  final String? body;
  final bool clearNickname;

  const _WhosPlayingBody({
    this.initial,
    this.title,
    this.body,
    this.clearNickname = false,
  });

  @override
  State<_WhosPlayingBody> createState() => _WhosPlayingBodyState();
}

class _WhosPlayingBodyState extends State<_WhosPlayingBody> {
  late final TextEditingController _nick;
  late String _avatarId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nick = TextEditingController(
      text: widget.clearNickname ? '' : (initial?.nickname ?? ''),
    );
    _avatarId = initial?.avatarId ?? defaultAvatarId;
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  void _submit() {
    final err = ShellProfile.validateNickname(_nick.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(
      ShellProfile(
        nickname: _nick.text.trim(),
        avatarId: _avatarId,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title ?? TableGamesCopy.whosPlayingTitle,
            style: GoogleFonts.playfairDisplay(
              color: goldAccent,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.body ?? TableGamesCopy.whosPlayingBody,
            style: GoogleFonts.sourceSans3(
              color: suitLight.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nick,
            autofocus: true,
            maxLength: ShellProfile.maxNicknameLength,
            decoration: InputDecoration(
              labelText: TableGamesCopy.nicknameHint,
              errorText: _error,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          AvatarPicker(
            selectedId: _avatarId,
            onSelected: (id) => setState(() => _avatarId = id),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Text(TableGamesCopy.saveProfile),
          ),
        ],
      ),
    );
  }
}
