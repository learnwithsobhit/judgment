import 'package:flutter_test/flutter_test.dart';
import 'package:shell_flutter/models/game_catalog.dart';
import 'package:shell_flutter/profile/shell_profile.dart';

void main() {
  test('default catalog has Judgement live and others coming soon', () {
    final games = defaultGameCatalog();
    expect(games, hasLength(4));

    final judgement = games.firstWhere((g) => g.id == 'judgement');
    expect(judgement.isLive, isTrue);

    for (final id in ['hazari', 'gulam_chor', 'gin_rummy']) {
      final g = games.firstWhere((e) => e.id == id);
      expect(g.status, GameStatus.comingSoon);
      expect(g.isLive, isFalse);
    }
  });

  test('nickname validation', () {
    expect(ShellProfile.validateNickname(''), isNotNull);
    expect(ShellProfile.validateNickname('   '), isNotNull);
    expect(ShellProfile.validateNickname('Ada'), isNull);
    expect(
      ShellProfile.validateNickname('x' * 25),
      isNotNull,
    );
  });
}
