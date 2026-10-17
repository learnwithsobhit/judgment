import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/util/seat_label.dart';
import 'package:judgement_flutter/widgets/emote_bar.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';

const _me = '00000000-0000-0000-0000-000000000001';

PlayerGameView _playingView({
  required int opponents,
  required List<String> names,
  int? trickCount,
}) {
  assert(names.length == opponents);
  return PlayerGameView.fromJson({
    'game_id': '00000000-0000-0000-0000-0000000000aa',
    'state_version': 12,
    'phase': 'playing',
    'own_hand': <dynamic>[],
    'own_seat': 0,
    'own_bid': 2,
    'own_tricks_won': 1,
    'own_avatar_id': 'face_01',
    'opponents': [
      for (var i = 0; i < opponents; i++)
        {
          'player_id': '00000000-0000-0000-0000-00000000000${i + 2}',
          'nickname': names[i],
          'seat': i + 1,
          'card_count': 4,
          'bid': 10,
          'tricks_won': 10,
          'connection_status': 'connected',
          'avatar_id': 'face_02',
        },
    ],
    'current_trick': [
      for (var i = 0; i < (trickCount ?? math.min(opponents, 4)); i++)
        {
          'player_id': i == 0
              ? _me
              : '00000000-0000-0000-0000-00000000000${i + 1}',
          'card': {
            'suit': 'hearts',
            'rank': ['ace', 'king', 'queen', 'jack', '10', '9', '8', '7'][i],
          },
        },
    ],
    'trump': 'hearts',
    'trump_card': {'suit': 'hearts', 'rank': 'ace'},
    'current_turn': _me,
    'bids': <dynamic>[],
    'scores': <dynamic>[],
    'round': {
      'round_index': 0,
      'total_rounds': 12,
      'cards_per_player': 4,
      'dealer': _me,
      'tricks_completed': 0,
    },
    'legal_actions': {'legal_bids': <dynamic>[], 'playable_cards': <dynamic>[]},
    'round_history': <dynamic>[],
  });
}

Future<GameController> _pump(
  WidgetTester tester, {
  required int opponents,
  required List<String> names,
  required String myNickname,
  int? trickCount,
}) async {
  final controller = GameController(
    api: ApiClient(),
    gameId: '00000000-0000-0000-0000-0000000000aa',
    myPlayerId: _me,
    myNickname: myNickname,
  );
  controller.view = _playingView(
    opponents: opponents,
    names: names,
    trickCount: trickCount,
  );
  controller.gameStartedAt = DateTime.now().subtract(
    const Duration(minutes: 4, seconds: 12),
  );
  controller.playerPace = [
    PlayerPace(playerId: _me, elapsedMs: 8000, decisions: 2),
    PlayerPace(
      playerId: '00000000-0000-0000-0000-000000000002',
      elapsedMs: 21000,
      decisions: 2,
    ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
      ),
      home: TableScreen(controller: controller),
    ),
  );
  await tester.pump();
  return controller;
}

Finder _seatName(String name) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data == name && widget.style?.fontSize == 12,
  );
}

Finder _cardName(String name) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data == name && widget.style?.fontSize == 10,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seat label uses the first name and the next initial', () {
    expect(seatLabel('Ankit Sunil Chaturvedi'), 'Ankit S');
    expect(seatLabel('Dharmendra Chaturvedi'), 'Dharmendra C');
    expect(seatLabel('shobhit chaturvedi'), 'shobhit C');
    expect(seatLabel('Madonna'), 'Madonna');
  });

  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) return;
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  });

  testWidgets(
    'four players keep clockwise seats and the name under each card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(
        tester,
        opponents: 3,
        names: const ['Left', 'Across', 'Right'],
        myNickname: 'Ankit Sunil Chaturvedi',
      );

      expect(find.text('bid 10'), findsNWidgets(3));
      expect(find.text('won 10'), findsNWidgets(3));
      for (final line in ['bid 10', 'won 10']) {
        for (final bid in tester.renderObjectList<RenderParagraph>(
          find.text(line),
        )) {
          expect(
            bid.didExceedMaxLines,
            isFalse,
            reason: '$line size ${bid.size} constraints ${bid.constraints}',
          );
        }
      }
      expect(find.text('dealer · bid 2 · won 1'), findsOneWidget);
    expect(find.text('04:12'), findsOneWidget);
    expect(
      find.text('Fastest Ankit S 00:08 · Slowest Left 00:21'),
      findsOneWidget,
    );
      expect(find.text('Ankit S'), findsWidgets);
      expect(find.text('Ankit Sunil Chaturvedi'), findsNothing);
      expect(_seatName('Left'), findsOneWidget);
      expect(_cardName('Left'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final left = tester.getCenter(_seatName('Left'));
      final across = tester.getCenter(_seatName('Across'));
      final right = tester.getCenter(_seatName('Right'));
      expect(left.dx, lessThan(across.dx));
      expect(right.dx, greaterThan(across.dx));
      expect(left.dy, greaterThan(across.dy));
      expect(right.dy, greaterThan(across.dy));
    },
  );

  testWidgets('eight players sit in non-overlapping clockwise slots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const names = ['Dharmendra Chaturvedi', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7'];
    await _pump(
      tester,
      opponents: 7,
      names: names,
      myNickname: 'You',
      trickCount: 8,
    );

    expect(find.text('bid 10'), findsNWidgets(7));
    expect(find.text('won 10'), findsNWidgets(7));
    for (final line in ['bid 10', 'won 10']) {
      for (final bid in tester.renderObjectList<RenderParagraph>(
        find.text(line),
      )) {
        expect(
          bid.didExceedMaxLines,
          isFalse,
          reason: '$line size ${bid.size} constraints ${bid.constraints}',
        );
      }
    }
    expect(_seatName('Dharmendra C'), findsOneWidget);
    expect(_cardName('Dharmendra C'), findsOneWidget);
    expect(find.text('Dharmendra Chaturvedi'), findsNothing);
    expect(tester.takeException(), isNull);

    double yOf(String name) => tester.getCenter(_seatName(name)).dy;
    double xOf(String name) => tester.getCenter(_seatName(name)).dx;

    // Left column, bottom to top: first joined opponent, then the next.
    expect(xOf('Dharmendra C'), lessThan(xOf('S4')));
    expect(yOf('Dharmendra C'), greaterThan(yOf('S2')));
    // Top row, left to right.
    expect(xOf('S3'), lessThan(xOf('S4')));
    expect(xOf('S4'), lessThan(xOf('S5')));
    expect(yOf('S3'), lessThan(yOf('Dharmendra C')));
    // Right column, top to bottom: S6 then S7.
    expect(xOf('S7'), greaterThan(xOf('S4')));
    expect(yOf('S6'), lessThan(yOf('S7')));

    final played = find.byType(PlayingCardWidget);
    expect(played, findsNWidgets(8));
    final width = tester.widget<PlayingCardWidget>(played.first).width;
    expect(width, inInclusiveRange(44, 48));
    final tops = <double>[
      for (var i = 0; i < 8; i++) tester.getRect(played.at(i)).top,
    ]..sort();
    expect(tops.where((y) => (y - tops.first).abs() < 1).length, 4);
    expect(tops.where((y) => (y - tops[4]).abs() < 1).length, 4);
    final emoteTop = tester.getTopLeft(find.byType(EmoteBar)).dy;
    for (var i = 0; i < 8; i++) {
      expect(tester.getRect(played.at(i)).bottom, lessThan(emoteTop));
    }

    const seatNames = ['Dharmendra C', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7'];
    final boxes = [
      for (final name in seatNames) tester.getRect(_seatName(name)),
    ];
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        expect(
          boxes[i].overlaps(boxes[j]),
          isFalse,
          reason: '${seatNames[i]} overlaps ${seatNames[j]}',
        );
      }
    }
  });
}
