import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/util/emote_lexicon.dart';

void main() {
  test('maps funny phrases to emoji bursts', () {
    expect(textToEmojis('nice trump'), contains('🔥'));
    expect(textToEmojis('gg'), contains('🙌'));
    expect(textToEmojis('oops'), contains('💀'));
  });

  test('ye mara keeps roast slam style without rewriting text', () {
    final style = resolveEmoteText('ye mara');
    expect(style.mood, 'roast');
    expect(style.stickerId, 'slam');
    expect(style.emojis, isNotEmpty);
  });

  test('unknown phrase still gets mood and no sticker', () {
    final style = resolveEmoteText('xyzzyq');
    expect(style.stickerId, isNull);
    expect(style.emojis, isNotEmpty);
  });
}
