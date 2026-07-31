import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../util/emote_lexicon.dart';
import '../util/sticker_pack.dart';

/// Hybrid blast: comic art-text (exact words) + optional curated sticker.
class CartoonTextBlastOverlay extends StatelessWidget {
  final GameController controller;

  const CartoonTextBlastOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bursts = controller.activeBursts
        .where((b) => b.text != null && b.text!.trim().isNotEmpty)
        .toList();
    if (bursts.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final burst in bursts) _CartoonTextBurst(burst: burst),
        ],
      ),
    );
  }
}

class CartoonTextPreview extends StatelessWidget {
  final String text;
  final EmoteStyle style;
  final double maxWidth;

  const CartoonTextPreview({
    super.key,
    required this.text,
    required this.style,
    this.maxWidth = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return _ComicBubble(
      text: text.trim(),
      mood: style.mood,
      stickerId: style.stickerId,
      scale: 0.72,
      maxWidth: maxWidth,
    );
  }
}

class _CartoonTextBurst extends StatefulWidget {
  final EmoteBurst burst;

  const _CartoonTextBurst({required this.burst});

  @override
  State<_CartoonTextBurst> createState() => _CartoonTextBurstState();
}

class _CartoonTextBurstState extends State<_CartoonTextBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.burst.ttlMs),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value.clamp(0.0, 1.0);
        // easeOutBack-style pop without feeding unbounded scale into layout.
        final enter = Curves.easeOutBack.transform((t * 1.6).clamp(0.0, 1.0));
        final scale = (0.7 + enter * 0.35).clamp(0.5, 1.15);
        final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
        final wobble = math.sin(t * math.pi * 5) * 0.035 * (1 - t);
        return Opacity(
          opacity: fade,
          child: Transform.rotate(
            angle: wobble,
            child: Transform.scale(
              scale: scale,
              child: _ComicBubble(
                text: widget.burst.text!.trim(),
                mood: widget.burst.mood ?? 'gg',
                stickerId: widget.burst.stickerId,
                scale: 1,
                maxWidth: 280,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComicBubble extends StatelessWidget {
  final String text;
  final String mood;
  final String? stickerId;
  final double scale;
  final double maxWidth;

  const _ComicBubble({
    required this.text,
    required this.mood,
    required this.stickerId,
    required this.scale,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final accent = moodColor(mood);
    final asset = stickerAssetPath(stickerId);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (stickerId != null)
            Padding(
              padding: EdgeInsets.only(bottom: 6 * scale),
              child: _StickerBadge(
                stickerId: stickerId!,
                assetPath: asset,
                size: 72 * scale,
              ),
            ),
          CustomPaint(
            painter: _BubblePainter(accent: accent),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18 * scale,
                14 * scale,
                18 * scale,
                20 * scale,
              ),
              child: _OutlinedComicText(
                text: text,
                fill: accent,
                fontSize: (22 * scale).clamp(14.0, 28.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerBadge extends StatelessWidget {
  final String stickerId;
  final String? assetPath;
  final double size;

  const _StickerBadge({
    required this.stickerId,
    required this.assetPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = stickerGlyph(stickerId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: Colors.black87, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: assetPath == null
          ? Center(child: Text(glyph, style: TextStyle(fontSize: size * 0.5)))
          : Image.asset(
              assetPath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(glyph, style: TextStyle(fontSize: size * 0.5)),
              ),
            ),
    );
  }
}

class _OutlinedComicText extends StatelessWidget {
  final String text;
  final Color fill;
  final double fontSize;

  const _OutlinedComicText({
    required this.text,
    required this.fill,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontFamily: 'Georgia',
      height: 1.1,
      letterSpacing: 0.4,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // Fake outline via shadows for a comic “fine art” feel.
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = Colors.black,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(color: Colors.white),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            color: fill,
            shadows: [
              Shadow(
                color: fill.withValues(alpha: 0.55),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  final Color accent;

  _BubblePainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 8),
      const Radius.circular(18),
    );
    final fill = Paint()..color = const Color(0xFFF7F1E3);
    final stroke = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    final accentStroke = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path()..addRRect(r);
    // Speech tail
    path.moveTo(size.width * 0.42, size.height - 10);
    path.lineTo(size.width * 0.48, size.height);
    path.lineTo(size.width * 0.58, size.height - 10);
    path.close();

    canvas.drawShadow(path, Colors.black54, 6, true);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    canvas.drawRRect(r.deflate(3), accentStroke);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) =>
      oldDelegate.accent != accent;
}
