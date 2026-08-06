import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';

import '../profile/shell_profile.dart';
import '../theme/table_games_theme.dart';
import '../ux/copy.dart';
import 'whos_playing_sheet.dart';

class ProfileChip extends StatelessWidget {
  final ShellProfile? profile;
  final ValueChanged<ShellProfile> onChanged;

  const ProfileChip({
    super.key,
    required this.profile,
    required this.onChanged,
  });

  Future<void> _edit(BuildContext context) async {
    final next = await showWhosPlayingSheet(context);
    if (next != null) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Material(
      color: feltGreen.withValues(alpha: 0.55),
      shape: StadiumBorder(
        side: BorderSide(color: goldAccent.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _edit(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p != null)
                PlayerAvatar(
                  avatarId: p.avatarId,
                  nickname: p.nickname,
                  radius: 14,
                )
              else
                Icon(Icons.person_outline, color: goldAccent, size: 22),
              const SizedBox(width: 8),
              Text(
                p == null
                    ? 'Set name'
                    : '${TableGamesCopy.playingAs} ${p.nickname}',
                style: GoogleFonts.sourceSans3(
                  color: goldAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
