import 'package:dehla_flutter/theme/dehla_theme.dart';
import 'package:dehla_flutter/widgets/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('teamRingFor', () {
    test('maps a/b case-insensitively', () {
      expect(teamRingFor('a'), teamRingWarm);
      expect(teamRingFor('A'), teamRingWarm);
      expect(teamRingFor('b'), teamRingCool);
      expect(teamRingFor('B'), teamRingCool);
      expect(teamRingFor(null), isNull);
      expect(teamRingFor('?'), isNull);
    });

    test('side labels are Warm/Teal not A/B', () {
      expect(teamSideLabel('a'), 'Warm');
      expect(teamSideLabel('b'), 'Teal');
      expect(teamSideLabel('a'), isNot(contains('A')));
      expect(teamSideLabel('b'), isNot(contains('B')));
    });
  });

  testWidgets('PlayerAvatar paints team ring under gold highlight', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerAvatar(
            avatarId: null,
            nickname: 'Alex',
            radius: 22,
            highlight: true,
            teamRing: teamRingWarm,
          ),
        ),
      ),
    );

    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final borders = containers
        .map((c) => (c.decoration as BoxDecoration?)?.border)
        .whereType<Border>()
        .toList();

    expect(
      borders.any((b) => b.top.color == teamRingWarm && b.top.width >= 3),
      isTrue,
      reason: 'warm team ring should be present',
    );
    expect(
      borders.any((b) => b.top.color == goldAccent && b.top.width >= 3),
      isTrue,
      reason: 'gold turn highlight should remain',
    );
  });

  testWidgets('PlayerAvatar cool ring without highlight', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerAvatar(
            avatarId: null,
            nickname: 'Bo',
            teamRing: teamRingCool,
          ),
        ),
      ),
    );

    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final borders = containers
        .map((c) => (c.decoration as BoxDecoration?)?.border)
        .whereType<Border>()
        .toList();

    expect(borders.any((b) => b.top.color == teamRingCool), isTrue);
    expect(find.text('Bo'), findsNothing); // letter glyph only inside avatar
  });
}
