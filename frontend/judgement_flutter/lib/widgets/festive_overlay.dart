import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/festival_catalog.dart';
import '../theme/festival_controller.dart';
import '../theme/judgement_palette.dart';

/// Margin marks only. Never sits on the live felt. [IgnorePointer] always.
class FestiveOverlay extends StatelessWidget {
  const FestiveOverlay({super.key = const Key('festive-overlay')});

  @override
  Widget build(BuildContext context) {
    final controller = FestivalController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.overlayAllowed) {
          return const SizedBox.shrink();
        }
        if (MediaQuery.disableAnimationsOf(context)) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: RepaintBoundary(
            child: _MotifLayer(
              motif: controller.theme.motif,
              palette: controller.palette,
            ),
          ),
        );
      },
    );
  }
}

class _MotifLayer extends StatefulWidget {
  const _MotifLayer({required this.motif, required this.palette});

  final FestivalMotif motif;
  final JudgementPalette palette;

  @override
  State<_MotifLayer> createState() => _MotifLayerState();
}

class _MotifLayerState extends State<_MotifLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        return CustomPaint(
          painter: FestiveMotifPainter(
            motif: widget.motif,
            palette: widget.palette,
            t: _ticker.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class FestiveMotifPainter extends CustomPainter {
  FestiveMotifPainter({
    required this.motif,
    required this.palette,
    required this.t,
    this.banner = false,
  });

  final FestivalMotif motif;
  final JudgementPalette palette;
  final double t;
  final bool banner;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (banner) {
      const count = 4;
      for (var i = 0; i < count; i++) {
        final x = size.width * (0.14 + i * 0.24);
        final drift = math.sin((t + i * 0.13) * math.pi * 2) * 3;
        _paintMark(canvas, Offset(x, 12.0 + drift), i);
      }
      return;
    }
    const count = 8;
    for (var i = 0; i < count; i++) {
      final alongTop = i < 4;
      final slot = alongTop ? i : i - 4;
      final x = size.width * (0.08 + slot * 0.28);
      final drift = math.sin((t + i * 0.13) * math.pi * 2) * 6;
      final y = alongTop
          ? 18.0 + drift
          : size.height - 22.0 + drift;
      _paintMark(canvas, Offset(x, y), i);
    }
  }

  void _paintMark(Canvas canvas, Offset origin, int index) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.gold.withValues(alpha: 0.12);
    switch (motif) {
      case FestivalMotif.none:
        return;
      case FestivalMotif.lamp:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: origin, width: 7, height: 11),
            const Radius.circular(2),
          ),
          paint,
        );
        canvas.drawCircle(
          origin.translate(0, -8),
          2.4,
          paint..color = palette.gold.withValues(alpha: 0.18),
        );
      case FestivalMotif.snow:
        canvas.drawCircle(origin, 2.2, paint);
      case FestivalMotif.powder:
        final colors = [
          const Color(0xFFE85D9A),
          const Color(0xFFF4D35E),
          const Color(0xFF5FA8D3),
        ];
        canvas.drawCircle(
          origin,
          3.2,
          paint..color = colors[index % colors.length].withValues(alpha: 0.14),
        );
      case FestivalMotif.spark:
        canvas.drawCircle(origin, 1.8, paint);
        canvas.drawLine(
          origin.translate(-4, 0),
          origin.translate(4, 0),
          paint
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      case FestivalMotif.crescent:
        canvas.drawCircle(origin, 5, paint);
        canvas.drawCircle(
          origin.translate(2.2, -0.8),
          3.6,
          Paint()..color = palette.feltDark.withValues(alpha: 0.85),
        );
    }
  }

  @override
  bool shouldRepaint(covariant FestiveMotifPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.motif != motif ||
        oldDelegate.palette != palette ||
        oldDelegate.banner != banner;
  }
}

/// Theme + motif under [MaterialApp]. Does not rebuild the navigator.
class FestivalHost extends StatefulWidget {
  const FestivalHost({super.key, required this.child});

  final Widget child;

  @override
  State<FestivalHost> createState() => _FestivalHostState();
}

class _FestivalHostState extends State<FestivalHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FestivalController.instance.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FestivalController.instance,
      builder: (context, _) {
        return AnimatedTheme(
          data: FestivalController.instance.palette.themeData,
          duration: const Duration(milliseconds: 400),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              const FestiveOverlay(),
            ],
          ),
        );
      },
    );
  }
}
