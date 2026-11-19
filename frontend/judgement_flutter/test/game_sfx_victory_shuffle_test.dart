import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/util/game_sfx.dart';

void main() {
  test('victory tracks shuffle without repeat within a cycle', () {
    final bag = VictoryTrackBag(GameSfx.victoryAssets, rng: math.Random(7));
    final firstCycle = List.generate(3, (_) => bag.next());

    expect(firstCycle.toSet(), GameSfx.victoryAssets.toSet());
    expect(firstCycle.length, GameSfx.victoryAssets.length);

    final secondCycle = List.generate(3, (_) => bag.next());
    expect(secondCycle.toSet(), GameSfx.victoryAssets.toSet());
  });

  test('different seeds can produce different orders', () {
    final bagA = VictoryTrackBag(GameSfx.victoryAssets, rng: math.Random(1));
    final bagB = VictoryTrackBag(GameSfx.victoryAssets, rng: math.Random(99));
    final cycleA = List.generate(3, (_) => bagA.next());
    final cycleB = List.generate(3, (_) => bagB.next());

    expect(cycleA.toSet(), GameSfx.victoryAssets.toSet());
    expect(cycleB.toSet(), GameSfx.victoryAssets.toSet());
    expect(cycleA, isNot(equals(cycleB)));
  });
}
