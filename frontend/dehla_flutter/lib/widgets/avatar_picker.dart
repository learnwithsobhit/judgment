import 'package:flutter/material.dart';

import '../util/avatar_pack.dart';
import 'player_avatar.dart';

class AvatarPicker extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const AvatarPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final id in imageAvatarIds.take(24))
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
        ),
      ),
    );
  }
}
