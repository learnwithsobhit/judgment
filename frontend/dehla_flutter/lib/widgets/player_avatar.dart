import 'package:flutter/material.dart';

import '../theme/dehla_theme.dart';
import '../util/avatar_pack.dart';
import '../util/card_assets.dart';

class PlayerAvatar extends StatefulWidget {
  final String? avatarId;
  final String nickname;
  final double radius;
  final bool highlight;
  final bool muted;

  /// Partnership ring (warm/teal). Drawn inside the turn highlight ring.
  final Color? teamRing;

  const PlayerAvatar({
    super.key,
    required this.avatarId,
    required this.nickname,
    this.radius = 20,
    this.highlight = false,
    this.muted = false,
    this.teamRing,
  });

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar> {
  @override
  Widget build(BuildContext context) {
    final letter = widget.nickname.isNotEmpty ? widget.nickname[0] : '?';
    final glyph = avatarGlyph(widget.avatarId, fallbackLetter: letter);
    final asset = avatarAssetPath(widget.avatarId);
    final team = widget.teamRing;

    Widget face = CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.muted
          ? Colors.grey.shade700
          : const Color(0xFF37474F),
      backgroundImage: (!widget.muted && asset != null)
          ? AssetImage(asset, package: dehlaAssetPackage)
          : null,
      child: widget.muted
          ? Icon(
              Icons.wifi_off,
              size: widget.radius * 0.9,
              color: Colors.white54,
            )
          : asset == null
          ? Text(glyph, style: TextStyle(fontSize: widget.radius * 0.95))
          : null,
    );

    // Mid: always-on team partnership ring.
    face = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(team != null ? 3.5 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: team ?? Colors.transparent,
          width: team != null ? 3.5 : 0,
        ),
      ),
      child: face,
    );

    // Outer: gold turn / selection highlight.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.highlight ? goldAccent : Colors.transparent,
          width: 3,
        ),
      ),
      child: face,
    );
  }
}
