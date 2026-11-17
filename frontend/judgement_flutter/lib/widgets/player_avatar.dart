import 'package:flutter/material.dart';

import '../util/avatar_pack.dart';
import '../util/photo_url.dart';
import '../util/seat_ornament.dart';

/// Tests replace NetworkImage so widget tests never hit the network.
@visibleForTesting
ImageProvider Function(String url)? debugProfilePhotoProvider;

/// Built-in pack avatar with optional cheer / flash scale bounce.
class PlayerAvatar extends StatefulWidget {
  final String? avatarId;
  final String nickname;
  final double radius;
  final bool highlight;
  final bool muted;
  final String? flashMood;
  final VoidCallback? onLongPress;

  /// Allowlisted Google/Telegram portrait. Painted only when [avatarId] is profile.
  final String? photoUrl;

  /// True after the profile photo paints; false if it errors. Pack faces skip this.
  final ValueChanged<bool>? onPhotoResolved;

  /// 1, 2, or 3 on the overall board. Anyone else has no cap.
  final int? boardRank;

  /// Special seat ornament (e.g. peacock_kalgi). Takes priority over [boardRank].
  final String? seatOrnament;

  /// Account on this seat. Not online/offline — guests stay without a badge.
  final bool signedIn;

  const PlayerAvatar({
    super.key,
    required this.avatarId,
    required this.nickname,
    this.radius = 20,
    this.highlight = false,
    this.muted = false,
    this.flashMood,
    this.onLongPress,
    this.photoUrl,
    this.onPhotoResolved,
    this.boardRank,
    this.seatOrnament,
    this.signedIn = false,
  });

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// Do not wrap [TweenSequence] in overshooting curves (e.g. easeOutBack) —
  /// that feeds t > 1 into [TweenSequence.transform] and asserts.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.28,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.28,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 60,
    ),
  ]).animate(_ctrl);

  String? _lastMood;

  @override
  void didUpdateWidget(covariant PlayerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashMood != null && widget.flashMood != _lastMood && mounted) {
      _lastMood = widget.flashMood;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.nickname.isNotEmpty ? widget.nickname[0] : '?';
    final glyph = avatarGlyph(widget.avatarId, fallbackLetter: letter);
    final asset = avatarAssetPath(widget.avatarId);
    final photoUrl = displayPhotoUrl(widget.photoUrl)?.trim() ?? '';
    final showPhoto =
        isProfileAvatar(widget.avatarId) &&
        photoUrl.isNotEmpty &&
        !widget.muted;
    final letterStyle = TextStyle(fontSize: widget.radius * 0.95);
    final fallback = widget.muted
        ? Icon(Icons.wifi_off, size: widget.radius * 0.9, color: Colors.white54)
        : Text(glyph, style: letterStyle);
    final portrait = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.highlight
              ? const Color(0xFFD4AF37)
              : Colors.transparent,
          width: 3,
        ),
      ),
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.muted
            ? Colors.grey.shade700
            : const Color(0xFF37474F),
        backgroundImage: (!widget.muted && asset != null)
            ? AssetImage(asset)
            : null,
        child: widget.muted
            ? fallback
            : asset != null
            ? null
            : showPhoto
            ? _ProfilePhoto(
                url: photoUrl,
                fallback: fallback,
                onResolved: widget.onPhotoResolved,
              )
            : fallback,
      ),
    );
    final ornament = resolveSeatOrnament(
      serverOrnament: widget.seatOrnament,
      nicknameOrDisplay: widget.nickname,
      signedIn: widget.signedIn,
    );
    final showPeacock = ornament == peacockKalgi;
    final rank = showPeacock ? null : _capRank(widget.boardRank);
    final badgeSize = (widget.radius * 0.72).clamp(12.0, 18.0);
    final capHeight = widget.radius * _rankBadgeHeightFactor;
    final kalgiHeight = widget.radius * _kalgiHeightFactor;
    // Portrait padding is the top of the circle. Sit the brim on that rim.
    const portraitPad = 3.0;
    final child = ScaleTransition(
      scale: _scale,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          portrait,
          if (showPeacock)
            Positioned(
              top: portraitPad - kalgiHeight,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: _PeacockKalgi(radius: widget.radius),
              ),
            )
          else if (rank != null)
            Positioned(
              top: portraitPad - capHeight,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: _RankCap(rank: rank, radius: widget.radius),
              ),
            ),
          if (widget.signedIn)
            Positioned(
              right: 0,
              bottom: 0,
              child: Tooltip(
                message: 'Signed in',
                child: Semantics(
                  label: 'Signed in',
                  child: Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5C6BC0),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1A120C),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.check,
                      size: badgeSize * 0.7,
                      color: Colors.white,
                      semanticLabel: 'Signed in',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.onLongPress == null) return child;
    return GestureDetector(onLongPress: widget.onLongPress, child: child);
  }
}

class _ProfilePhoto extends StatefulWidget {
  const _ProfilePhoto({
    required this.url,
    required this.fallback,
    this.onResolved,
  });

  final String url;
  final Widget fallback;
  final ValueChanged<bool>? onResolved;

  @override
  State<_ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<_ProfilePhoto> {
  bool _notified = false;

  @override
  void didUpdateWidget(covariant _ProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _notified = false;
    }
  }

  void _notify(bool ok) {
    if (_notified) return;
    _notified = true;
    final callback = widget.onResolved;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final override = debugProfilePhotoProvider;
    final provider = override != null
        ? override(widget.url)
        : NetworkImage(widget.url);
    return ClipOval(
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: widget.fallback),
            Image(
              image: provider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  _notify(true);
                  return child;
                }
                return const SizedBox.shrink();
              },
              errorBuilder: (context, error, stack) {
                _notify(false);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

int? _capRank(int? rank) {
  if (rank == null || rank < 1 || rank > 3) return null;
  return rank;
}

/// Flip to `true` to restore the old painted baseball-style overall caps.
const usePaintedRankCaps = false;

const _capWidthFactor = 1.45;
const _capHeightFactor = 1.07;
/// Imperial crown PNGs are taller/narrower than the painted baseball caps.
const _crownWidthFactor = 1.38;
const _crownHeightFactor = 1.32;
const _kalgiWidthFactor = 1.55;
const _kalgiHeightFactor = 1.55;

double get _rankBadgeWidthFactor =>
    usePaintedRankCaps ? _capWidthFactor : _crownWidthFactor;
double get _rankBadgeHeightFactor =>
    usePaintedRankCaps ? _capHeightFactor : _crownHeightFactor;

/// F1: real peacock plume + slim gold clasp for allowlisted signed-in seats.
class _PeacockKalgi extends StatelessWidget {
  final double radius;

  const _PeacockKalgi({required this.radius});

  @override
  Widget build(BuildContext context) {
    final w = radius * _kalgiWidthFactor;
    final h = radius * _kalgiHeightFactor;
    final claspH = (radius * 0.28).clamp(6.0, 12.0);
    return Tooltip(
      message: 'Special kalgi',
      child: Semantics(
        label: 'Special kalgi',
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: claspH * 0.35,
                child: Image.asset(
                  'assets/badges/peacock_kalgi_tip.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              Positioned(
                bottom: 0,
                child: CustomPaint(
                  size: Size(w * 0.52, claspH),
                  painter: const _KalgiClaspPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KalgiClaspPainter extends CustomPainter {
  const _KalgiClaspPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.15, w, h * 0.7),
      Radius.circular(h * 0.25),
    );
    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF3C4), Color(0xFFF6C431), Color(0xFF8C5E08)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(r, gold);
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFF1A120C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (h * 0.12).clamp(1.0, 1.6),
    );
    canvas.drawLine(
      Offset(w * 0.12, h * 0.38),
      Offset(w * 0.88, h * 0.38),
      Paint()
        ..color = const Color(0xFFFFF8D0).withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
    final jewel = Offset(w * 0.5, h * 0.5);
    canvas.drawCircle(jewel, h * 0.22, Paint()..color = const Color(0xFFC62828));
    canvas.drawCircle(
      jewel,
      h * 0.22,
      Paint()
        ..color = const Color(0xFF1A120C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      jewel.translate(-h * 0.06, -h * 0.06),
      h * 0.07,
      Paint()..color = const Color(0xFFFFCDD2).withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _KalgiClaspPainter oldDelegate) => false;
}

String _rankCrownAsset(int rank) => switch (rank) {
  1 => 'assets/badges/rank_crown_gold.png',
  2 => 'assets/badges/rank_crown_silver.png',
  _ => 'assets/badges/rank_crown_bronze.png',
};

/// Overall 1st/2nd/3rd badge on the portrait rim. Default: imperial crown PNGs.
/// Set [usePaintedRankCaps] to restore the legacy baseball-cap CustomPaint.
class _RankCap extends StatelessWidget {
  final int rank;
  final double radius;

  const _RankCap({required this.rank, required this.radius});

  @override
  Widget build(BuildContext context) {
    final label = switch (rank) {
      1 => '1st overall',
      2 => '2nd overall',
      _ => '3rd overall',
    };
    final w = radius * _rankBadgeWidthFactor;
    final h = radius * _rankBadgeHeightFactor;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: w,
          height: h,
          child: usePaintedRankCaps
              ? _PaintedRankCap(rank: rank)
              : Image.asset(
                  _rankCrownAsset(rank),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      SizedBox.expand(child: _PaintedRankCap(rank: rank)),
                ),
        ),
      ),
    );
  }
}

/// Legacy painted baseball-style cap (kept for revert / Image.asset fallback).
class _PaintedRankCap extends StatelessWidget {
  final int rank;

  const _PaintedRankCap({required this.rank});

  @override
  Widget build(BuildContext context) {
    final (dome, brim, shade, shine) = switch (rank) {
      1 => (
        const Color(0xFFF6C431),
        const Color(0xFFC88810),
        const Color(0xFF8C5E08),
        const Color(0xFFFFF1A8),
      ),
      2 => (
        const Color(0xFFF3F4F6),
        const Color(0xFFB0B6BC),
        const Color(0xFF6E757C),
        const Color(0xFFFFFFFF),
      ),
      _ => (
        const Color(0xFFE39A55),
        const Color(0xFFA85A28),
        const Color(0xFF6E3A16),
        const Color(0xFFF8C99A),
      ),
    };
    return CustomPaint(
      painter: _CapPainter(
        dome: dome,
        brim: brim,
        shade: shade,
        shine: shine,
      ),
    );
  }
}

class _CapPainter extends CustomPainter {
  final Color dome;
  final Color brim;
  final Color shade;
  final Color shine;

  const _CapPainter({
    required this.dome,
    required this.brim,
    required this.shade,
    required this.shine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.045).clamp(1.4, 2.6);
    final outline = Paint()
      ..color = const Color(0xFF1A120C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;

    final visor = Path()
      ..moveTo(w * 0.06, h * 0.58)
      ..quadraticBezierTo(w * 0.50, h * 0.44, w * 0.94, h * 0.58)
      ..quadraticBezierTo(w * 0.50, h * 1.0, w * 0.06, h * 0.58)
      ..close();
    final visorShade = Path()
      ..moveTo(w * 0.16, h * 0.68)
      ..quadraticBezierTo(w * 0.50, h * 0.58, w * 0.84, h * 0.68)
      ..quadraticBezierTo(w * 0.50, h * 0.96, w * 0.16, h * 0.68)
      ..close();
    canvas.drawPath(visor, Paint()..color = brim);
    canvas.drawPath(visorShade, Paint()..color = shade);
    canvas.drawPath(visor, outline);

    final crown = Path()
      ..moveTo(w * 0.22, h * 0.62)
      ..cubicTo(w * 0.14, h * 0.34, w * 0.24, h * 0.06, w * 0.50, h * 0.04)
      ..cubicTo(w * 0.76, h * 0.06, w * 0.86, h * 0.34, w * 0.78, h * 0.62)
      ..close();
    canvas.drawPath(crown, Paint()..color = dome);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.38, h * 0.24),
        width: w * 0.16,
        height: h * 0.12,
      ),
      Paint()..color = shine,
    );
    canvas.drawLine(
      Offset(w * 0.50, h * 0.10),
      Offset(w * 0.50, h * 0.58),
      Paint()
        ..color = const Color(0xFF1A120C).withValues(alpha: 0.28)
        ..strokeWidth = stroke * 0.55,
    );
    final button = Offset(w * 0.50, h * 0.08);
    canvas.drawCircle(button, w * 0.045, Paint()..color = shade);
    canvas.drawCircle(
      button,
      w * 0.045,
      Paint()
        ..color = const Color(0xFF1A120C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.55,
    );
    canvas.drawPath(crown, outline);
  }

  @override
  bool shouldRepaint(covariant _CapPainter oldDelegate) =>
      oldDelegate.dome != dome ||
      oldDelegate.brim != brim ||
      oldDelegate.shade != shade ||
      oldDelegate.shine != shine;
}
