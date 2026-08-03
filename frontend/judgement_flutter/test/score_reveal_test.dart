import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/util/score_reveal.dart';

void main() {
  group('ScoreReveal.unlockAfterRoundFor', () {
    test('automatic seat sizes', () {
      expect(ScoreReveal.unlockAfterRoundFor(17), 9); // 3p
      expect(ScoreReveal.unlockAfterRoundFor(12), 6); // 4p
      expect(ScoreReveal.unlockAfterRoundFor(10), 5); // 5p
      expect(ScoreReveal.unlockAfterRoundFor(8), 4); // 6p
      expect(ScoreReveal.unlockAfterRoundFor(7), 4); // 7p
      expect(ScoreReveal.unlockAfterRoundFor(6), 3); // 8p
    });

    test('manual / short schedules', () {
      expect(ScoreReveal.unlockAfterRoundFor(12), 6);
      expect(ScoreReveal.unlockAfterRoundFor(4), 2);
      expect(ScoreReveal.unlockAfterRoundFor(2), 1);
      expect(ScoreReveal.unlockAfterRoundFor(1), 1);
    });
  });

  group('ScoreReveal.shouldShowTotals', () {
    test('hidden before halftime', () {
      expect(
        ScoreReveal.shouldShowTotals(
          isFinished: false,
          totalRounds: 8,
          completedRounds: 3,
          cardsPerPlayer: 5,
        ),
        isFalse,
      );
    });

    test('visible at and after halftime', () {
      expect(
        ScoreReveal.shouldShowTotals(
          isFinished: false,
          totalRounds: 8,
          completedRounds: 4,
          cardsPerPlayer: 4,
        ),
        isTrue,
      );
      expect(
        ScoreReveal.shouldShowTotals(
          isFinished: false,
          totalRounds: 8,
          completedRounds: 5,
          cardsPerPlayer: 3,
        ),
        isTrue,
      );
    });

    test('≤3-card phase unlocks early', () {
      expect(
        ScoreReveal.shouldShowTotals(
          isFinished: false,
          totalRounds: 12,
          completedRounds: 2,
          cardsPerPlayer: 3,
        ),
        isTrue,
      );
    });

    test('finished always shows', () {
      expect(
        ScoreReveal.shouldShowTotals(
          isFinished: true,
          totalRounds: 8,
          completedRounds: 0,
          cardsPerPlayer: 8,
        ),
        isTrue,
      );
    });
  });
}
