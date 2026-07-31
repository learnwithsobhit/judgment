import 'package:flutter/material.dart';

import '../models/protocol.dart';
import '../util/card_assets.dart';

/// A rendered playing card face from the vendored PNG deck.
///
/// Suit + rank remain available via [CardModel.label] for accessibility so
/// colour is never the only cue (PLAN.md §24).
class PlayingCardWidget extends StatelessWidget {
  final CardModel card;
  final double width;
  final bool highlighted;
  final bool disabled;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    super.key,
    required this.card,
    this.width = 64,
    this.highlighted = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 1.45;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final assetPath = cardFaceAssetPath(card);

    final face = AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(
          color: highlighted ? const Color(0xFFFFC857) : Colors.black26,
          width: highlighted ? 3 : 1,
        ),
        boxShadow: [
          if (highlighted)
            const BoxShadow(color: Color(0x88FFC857), blurRadius: 12)
          else
            const BoxShadow(
                color: Colors.black38, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.06),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.white,
              child: Image.asset(
                assetPath,
                width: width,
                height: height,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _CardFallback(card: card),
              ),
            ),
            if (disabled) const ColoredBox(color: Color(0x99B0B0B0)),
          ],
        ),
      ),
    );

    return Semantics(
      label: card.label,
      button: onTap != null,
      enabled: !disabled,
      // Own the accessible name so colour/rank Text nodes do not fragment it.
      excludeSemantics: true,
      child: GestureDetector(onTap: onTap, child: face),
    );
  }
}

/// Last-resort readable face if an asset fails to load.
class _CardFallback extends StatelessWidget {
  final CardModel card;

  const _CardFallback({required this.card});

  @override
  Widget build(BuildContext context) {
    final color =
        card.isRed ? const Color(0xFFC62828) : const Color(0xFF1A1A2E);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.rankLabel,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          Text(card.suitSymbol, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }
}

/// A face-down card back, used for opponents' hidden cards.
class CardBack extends StatelessWidget {
  final double width;

  const CardBack({super.key, this.width = 28});

  @override
  Widget build(BuildContext context) {
    final height = width * 1.45;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0.5, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.06),
        child: Image.asset(
          cardBackAssetPath,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF1A237E),
          ),
        ),
      ),
    );
  }
}
