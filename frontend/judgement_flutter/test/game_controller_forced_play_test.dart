import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/state/game_controller.dart';

void main() {
  test('NotYourTurn and CardNotInHand are quiet for a pending play_card', () {
    expect(isBenignPlayCardReject('not_your_turn'), isTrue);
    expect(isBenignPlayCardReject('NOT_YOUR_TURN'), isTrue);
    expect(isBenignPlayCardReject('card_not_in_hand'), isTrue);
    expect(isBenignPlayCardReject('must_follow_suit'), isFalse);
    expect(isBenignPlayCardReject(null), isFalse);
  });

  test('snapshot where the singleton left the hand clears pending play', () {
    const pending = {'type': 'play_card', 'card_id': 'ace-of-hearts'};
    expect(
      pendingPlayCardLeftHand(
        pendingAction: pending,
        ownHandIds: const ['ace-of-hearts', 'two-of-spades'],
      ),
      isFalse,
    );
    expect(
      pendingPlayCardLeftHand(
        pendingAction: pending,
        ownHandIds: const ['two-of-spades'],
      ),
      isTrue,
    );
    expect(
      pendingPlayCardLeftHand(
        pendingAction: {'type': 'place_bid', 'bid': 2},
        ownHandIds: const [],
      ),
      isFalse,
    );
  });
}
