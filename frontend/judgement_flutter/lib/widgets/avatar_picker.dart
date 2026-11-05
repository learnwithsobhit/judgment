import 'package:flutter/material.dart';

import '../util/avatar_pack.dart';
import 'player_avatar.dart';

/// Grid of built-in character avatars for landing / lobby selection.
class AvatarPicker extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// When true, only illustrated faces (hides legacy emoji section).
  final bool imagesOnly;

  /// Signed-in Google/Telegram portrait. Guests and email accounts leave this empty.
  final String? photoUrl;

  /// Letter fallback for the photo row.
  final String nickname;

  /// New accounts with a photo: select `profile` once it paints.
  final bool autoSelectProfile;

  const AvatarPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.imagesOnly = true,
    this.photoUrl,
    this.nickname = 'Player',
    this.autoSelectProfile = false,
  });

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _photoReady = false;
  bool _photoFailed = false;
  bool _autoSelected = false;
  bool _pickedFace = false;

  bool get _hasPhoto {
    final url = widget.photoUrl?.trim() ?? '';
    return url.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant AvatarPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _photoReady = false;
      _photoFailed = false;
      _autoSelected = false;
    }
  }

  void _onPhotoResolved(bool ok) {
    if (!mounted) return;
    final already = _photoReady == ok && _photoFailed == !ok;
    if (!already) {
      setState(() {
        _photoReady = ok;
        _photoFailed = !ok;
      });
    }
    if (ok &&
        widget.autoSelectProfile &&
        !_autoSelected &&
        !_pickedFace &&
        !isProfileAvatar(widget.selectedId)) {
      _autoSelected = true;
      widget.onSelected(profileAvatarId);
    }
  }

  void _tapPhoto() {
    if (!_photoReady || _photoFailed) return;
    widget.onSelected(profileAvatarId);
  }

  void _tapFace(String id) {
    _pickedFace = true;
    widget.onSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.imagesOnly ? imageAvatarIds : avatarIds;
    final photoSelected = isProfileAvatar(widget.selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasPhoto) ...[
          _PhotoRow(
            selected: photoSelected,
            failed: _photoFailed,
            ready: _photoReady,
            photoUrl: widget.photoUrl!.trim(),
            nickname: widget.nickname,
            onTap: _tapPhoto,
            onPhotoResolved: _onPhotoResolved,
          ),
          const SizedBox(height: 12),
          Text(
            'Or pick a character',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
        ] else ...[
          Text('Your avatar', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final id in ids)
              InkWell(
                onTap: () => _tapFace(id),
                borderRadius: BorderRadius.circular(28),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selectedId == id
                        ? const Color(0xFFD4AF37).withValues(alpha: 0.35)
                        : Colors.white12,
                    border: Border.all(
                      color: widget.selectedId == id
                          ? const Color(0xFFD4AF37)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: PlayerAvatar(avatarId: id, nickname: id, radius: 20),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.selected,
    required this.failed,
    required this.ready,
    required this.photoUrl,
    required this.nickname,
    required this.onTap,
    required this.onPhotoResolved,
  });

  final bool selected;
  final bool failed;
  final bool ready;
  final String photoUrl;
  final String nickname;
  final VoidCallback onTap;
  final ValueChanged<bool> onPhotoResolved;

  @override
  Widget build(BuildContext context) {
    final caption = failed
        ? 'Photo didn’t load. Pick a character for now.'
        : selected
        ? 'This is what other players see.'
        : 'Tap to use your photo instead.';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? const Color(0xFFD4AF37).withValues(alpha: 0.35)
                    : Colors.white12,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFD4AF37)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: PlayerAvatar(
                avatarId: profileAvatarId,
                photoUrl: photoUrl,
                nickname: nickname,
                radius: 20,
                onPhotoResolved: onPhotoResolved,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use my photo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
