import 'package:flutter/material.dart';

import '../util/avatar_pack.dart';
import 'player_avatar.dart';

/// Grid of built-in character avatars for landing / lobby selection.
class AvatarPicker extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// When true, only illustrated faces (hides legacy emoji section).
  final bool imagesOnly;

  const AvatarPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.imagesOnly = true,
  });

  @override
  Widget build(BuildContext context) {
    final ids = imagesOnly ? imageAvatarIds : avatarIds;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final id in ids)
          InkWell(
            onTap: () => onSelected(id),
            borderRadius: BorderRadius.circular(28),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectedId == id
                    ? const Color(0xFFD4AF37).withValues(alpha: 0.35)
                    : Colors.white12,
                border: Border.all(
                  color: selectedId == id
                      ? const Color(0xFFD4AF37)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: PlayerAvatar(
                avatarId: id,
                nickname: id,
                radius: 20,
              ),
            ),
          ),
      ],
    );
  }
}
