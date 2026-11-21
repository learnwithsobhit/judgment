import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/util/emote_lexicon.dart';

void main() {
  test('reaction catalog is unique and includes thumbs-up', () {
    final all = allReactionEmojis();
    expect(all.toSet(), hasLength(all.length));
    expect(all.length, inInclusiveRange(50, 70));
    expect(all, contains('👍'));
    expect(all, contains('❤️'));
    expect(all, containsAll(quickReactEmojis));
    expect(reactionCategories.map((c) => c.label).toList(), [
      'Smileys',
      'Gestures',
      'Hearts',
      'Celebrate',
    ]);
  });
}
