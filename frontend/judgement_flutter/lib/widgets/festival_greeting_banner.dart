import 'package:flutter/material.dart';

import '../theme/festival_controller.dart';
import '../theme/judgement_palette.dart';
import 'festive_overlay.dart';

/// One-shot festive wish. Lives in landing and lobby flow, never on the felt.
class FestivalGreetingBanner extends StatefulWidget {
  const FestivalGreetingBanner({super.key});

  static const sparkleKey = Key('festive-greeting-sparkle');

  @override
  State<FestivalGreetingBanner> createState() => _FestivalGreetingBannerState();
}

class _FestivalGreetingBannerState extends State<FestivalGreetingBanner>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _sparkle;
  bool _started = false;
  bool _skipMotion = false;
  bool _sparkleVisible = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _sparkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final festive = FestivalController.instance;
    _skipMotion =
        festive.calm ||
        festive.greetingPlayed ||
        MediaQuery.disableAnimationsOf(context);
    if (_skipMotion) {
      festive.markGreetingPlayed();
      return;
    }
    _enter.forward().whenComplete(_startSparkle);
  }

  void _startSparkle() {
    if (!mounted) return;
    if (FestivalController.instance.calm) {
      FestivalController.instance.markGreetingPlayed();
      return;
    }
    setState(() => _sparkleVisible = true);
    _sparkle.forward().whenComplete(() {
      FestivalController.instance.markGreetingPlayed();
      if (mounted) setState(() => _sparkleVisible = false);
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final festive = FestivalController.instance;
    return ListenableBuilder(
      listenable: festive,
      builder: (context, _) {
        if (!festive.showGreeting) {
          return const SizedBox.shrink();
        }
        final theme = festive.theme;
        final palette = context.palette;
        final card = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.gold.withValues(alpha: 0.5)),
            ),
            child: Stack(
              children: [
                if (_sparkleVisible)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _sparkle,
                          builder: (context, _) {
                            return CustomPaint(
                              key: FestivalGreetingBanner.sparkleKey,
                              painter: FestiveMotifPainter(
                                motif: theme.motif,
                                palette: palette,
                                t: _sparkle.value,
                                banner: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              theme.greeting,
                              style: TextStyle(
                                color: palette.title,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              theme.wish,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: festive.dismissCaption,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        final padded = Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: card,
        );
        if (_skipMotion) return padded;
        return FadeTransition(
          opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: _enter, curve: Curves.easeOut),
            ),
            child: padded,
          ),
        );
      },
    );
  }
}
