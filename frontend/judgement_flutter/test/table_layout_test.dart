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
import 'package:judgement_flutter/util/table_place.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';

const _me = '00000000-0000-0000-0000-000000000001';

PlayerGameView _playingView({
  required int opponents,
  required List<String> names,
  int? trickCount,
  List<Map<String, dynamic>>? scores,
  List<Map<String, dynamic>>? roundHistory,
  Map<String, dynamic>? leader,
  String? dealer,
  Map<String, int>? ladderRanks,
  int? ownLadderRank,
  int? cardsPerPlayer,
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
    if (ownLadderRank != null) 'own_ladder_rank': ownLadderRank,
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
          'ladder_rank':
              ?ladderRanks?['00000000-0000-0000-0000-00000000000${i + 2}'],
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
    'scores': scores ?? <dynamic>[],
    'round': {
      'round_index': 0,
      'total_rounds': 12,
      'cards_per_player': cardsPerPlayer ?? 4,
      'dealer': dealer ?? _me,
      'tricks_completed': 0,
    },
    'legal_actions': {'legal_bids': <dynamic>[], 'playable_cards': <dynamic>[]},
    'round_history': roundHistory ?? <dynamic>[],
    if (leader != null) 'leader': leader,
  });
}

Future<GameController> _pump(
  WidgetTester tester, {
  required int opponents,
  required List<String> names,
  required String myNickname,
  int? trickCount,
  PlayerGameView? view,
}) async {
  final controller = GameController(
    api: ApiClient(),
    gameId: '00000000-0000-0000-0000-0000000000aa',
    myPlayerId: _me,
    myNickname: myNickname,
  );
  controller.view =
      view ??
      _playingView(opponents: opponents, names: names, trickCount: trickCount);
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

      expect(find.textContaining('So far'), findsNothing);
      expect(find.text('Round 1/12'), findsOneWidget);
      final roundLabel = tester.renderObject<RenderParagraph>(
        find.text('Round 1/12'),
      );
      expect(roundLabel.didExceedMaxLines, isFalse);
      expect(roundLabel.size.width, greaterThan(70));
      expect(find.text('bid 10 · won 10'), findsNWidgets(3));
      for (final bid in tester.renderObjectList<RenderParagraph>(
        find.text('bid 10 · won 10'),
      )) {
        expect(
          bid.didExceedMaxLines,
          isFalse,
          reason: 'bid/won size ${bid.size} constraints ${bid.constraints}',
        );
      }
      expect(find.text('dealer · bid 2 · won 1'), findsOneWidget);
      expect(find.text('04:12'), findsOneWidget);
      // Pace lives in the scoreboard drawer, not the live top bar.
      expect(
        find.text('Fastest Ankit S 00:08 · Slowest Left 00:21'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Scoreboard'));
      await tester.pumpAndSettle();
      expect(
        find.text('Fastest Ankit S 00:08 · Slowest Left 00:21'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(Drawer))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Ankit S'), findsWidgets);
      expect(find.text('Ankit Sunil Chaturvedi'), findsNothing);
      expect(_seatName('Left'), findsOneWidget);
      expect(_cardName('Left'), findsOneWidget);
      expect(find.text('React'), findsNothing);
      expect(find.byTooltip('Reactions'), findsOneWidget);
      expect(find.byTooltip('Voice note'), findsOneWidget);
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

    // Crowded 8-max tables use compact bN·wM seat stats.
    expect(find.text('b10·w10'), findsNWidgets(7));
    for (final bid in tester.renderObjectList<RenderParagraph>(
      find.text('b10·w10'),
    )) {
      expect(
        bid.didExceedMaxLines,
        isFalse,
        reason: 'compact bid/won size ${bid.size} constraints ${bid.constraints}',
      );
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
    final dockTop = tester
        .getTopLeft(find.byKey(const ValueKey('table-action-dock')))
        .dy;
    for (var i = 0; i < 8; i++) {
      expect(tester.getRect(played.at(i)).bottom, lessThan(dockTop));
    }

    const seatNames = ['Dharmendra C', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7'];
    for (final name in seatNames) {
      expect(
        tester.getRect(_seatName(name)).bottom,
        lessThan(dockTop),
        reason: '$name seat chip must stay above the action dock',
      );
    }
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

  testWidgets('phone bidding keeps every placed bid next to the picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const ranks = [
      'ace',
      'king',
      'queen',
      'jack',
      '10',
      '9',
      '8',
      '7',
      '6',
      '5',
    ];
    const suits = ['spades', 'hearts', 'clubs', 'diamonds'];
    final controller = GameController(
      api: ApiClient(),
      gameId: '00000000-0000-0000-0000-0000000000aa',
      myPlayerId: _me,
      myNickname: 'shobhit chaturvedi',
    );
    controller.view = PlayerGameView.fromJson({
      'game_id': '00000000-0000-0000-0000-0000000000aa',
      'state_version': 4,
      'phase': 'bidding',
      'own_hand': [
        for (var i = 0; i < 10; i++)
          {'suit': suits[i % suits.length], 'rank': ranks[i]},
      ],
      'own_seat': 0,
      'own_bid': null,
      'own_tricks_won': 0,
      'own_avatar_id': 'face_01',
      'opponents': [
        {
          'player_id': '00000000-0000-0000-0000-000000000002',
          'nickname': 'Left',
          'seat': 1,
          'card_count': 10,
          'bid': 1,
          'tricks_won': 0,
          'connection_status': 'connected',
          'avatar_id': 'face_02',
        },
        {
          'player_id': '00000000-0000-0000-0000-000000000003',
          'nickname': 'Across',
          'seat': 2,
          'card_count': 10,
          'bid': 3,
          'tricks_won': 0,
          'connection_status': 'connected',
          'avatar_id': 'face_03',
        },
        {
          'player_id': '00000000-0000-0000-0000-000000000004',
          'nickname': 'Right',
          'seat': 3,
          'card_count': 10,
          'bid': null,
          'tricks_won': 0,
          'connection_status': 'connected',
          'avatar_id': 'face_04',
        },
      ],
      'current_trick': <dynamic>[],
      'trump': 'clubs',
      'current_turn': _me,
      'bids': [
        {'player_id': '00000000-0000-0000-0000-000000000002', 'bid': 1},
        {'player_id': '00000000-0000-0000-0000-000000000003', 'bid': 3},
      ],
      'scores': <dynamic>[],
      'round': {
        'round_index': 0,
        'total_rounds': 12,
        'cards_per_player': 10,
        'dealer': _me,
        'tricks_completed': 0,
      },
      'legal_actions': {
        'legal_bids': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'playable_cards': <dynamic>[],
      },
      'round_history': <dynamic>[],
    });

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

    expect(find.text('So far 4 / 10'), findsOneWidget);
    final soFarStyle = tester.widget<Text>(find.text('So far 4 / 10')).style;
    expect(soFarStyle?.fontSize, greaterThanOrEqualTo(15));
    expect(
      tester
          .element(find.text('So far 4 / 10'))
          .findAncestorWidgetOfExactType<FittedBox>(),
      isNull,
    );
    expect(find.text('Left 1'), findsOneWidget);
    expect(find.text('Across 3'), findsOneWidget);
    expect(find.text('you —'), findsOneWidget);
    expect(find.text('Right —'), findsOneWidget);
    final leftPill = tester.widget<Text>(find.text('Left 1'));
    expect(leftPill.style?.fontSize, greaterThanOrEqualTo(13));
    expect(find.text('bid 1 · won 0'), findsOneWidget);
    expect(find.text('bid 3 · won 0'), findsOneWidget);
    expect(find.text('10 cards'), findsNothing);
    expect(find.text('— · 10 cards'), findsNothing);
    expect(find.text('React'), findsNothing);
    expect(find.byTooltip('Reactions'), findsOneWidget);
    expect(find.byTooltip('Voice note'), findsOneWidget);

    final recap = tester.getRect(find.text('So far 4 / 10'));
    final left = tester.getRect(find.text('Left 1'));
    final across = tester.getRect(find.text('Across 3'));
    final you = tester.getRect(find.text('you —'));
    final right = tester.getRect(find.text('Right —'));
    final react = tester.getRect(find.byTooltip('Reactions'));
    final mic = tester.getRect(find.byTooltip('Voice note'));
    final mute = tester.getRect(find.byTooltip('Mute table noise'));
    final bidZero = tester.getRect(find.widgetWithText(FilledButton, '0'));
    final bidSix = tester.getRect(find.widgetWithText(FilledButton, '6'));
    final bidTen = tester.getRect(find.widgetWithText(FilledButton, '10'));
    for (final rect in [recap, bidZero, bidSix, bidTen, react, mic, mute]) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
      expect(rect.bottom, lessThanOrEqualTo(700));
    }
    for (final pill in [left, across, you, right]) {
      expect(
        (pill.center.dy - recap.center.dy).abs(),
        lessThanOrEqualTo(8),
        reason: 'So far and bid pills must share one line, not stack',
      );
    }
    expect(left.left, greaterThan(recap.right));
    expect(
      [left, across, you, right].map((r) => r.bottom).reduce(math.max) -
          [left, across, you, right].map((r) => r.top).reduce(math.min),
      lessThanOrEqualTo(32),
    );
    expect(recap.bottom, lessThan(bidZero.top));
    expect((bidZero.top - bidSix.top).abs(), lessThan(1));
    expect(bidTen.top, greaterThan(bidZero.top + 20));
    expect((react.center.dy - mute.center.dy).abs(), lessThanOrEqualTo(4));
    expect((mic.center.dy - react.center.dy).abs(), lessThanOrEqualTo(4));
    expect(mic.left, greaterThan(react.right));
    expect(react.bottom, lessThanOrEqualTo(bidZero.top));
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '2'));
    await tester.pump();
    final confirm = tester.getRect(
      find.widgetWithText(FilledButton, 'Confirm bid'),
    );
    expect(react.bottom, lessThanOrEqualTo(confirm.top));

    await tester.ensureVisible(find.byTooltip('Reactions'));
    await tester.tap(find.byTooltip('Reactions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Table reacts'), findsOneWidget);
    expect(find.text('Smileys'), findsOneWidget);
    expect(find.text('Gestures'), findsOneWidget);
    expect(find.text('😂'), findsWidgets);
    expect(find.byTooltip('Voice note'), findsOneWidget);
    await tester.tap(find.text('Gestures'));
    await tester.pump();
    expect(find.text('👍'), findsOneWidget);
    Navigator.of(tester.element(find.text('Table reacts'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Table reacts'), findsNothing);
  });

  testWidgets(
    'eight-player bidding keeps So far and bid pills on one scrollable line',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const names = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7'];
      final controller = GameController(
        api: ApiClient(),
        gameId: '00000000-0000-0000-0000-0000000000aa',
        myPlayerId: _me,
        myNickname: 'You',
      );
      controller.view = PlayerGameView.fromJson({
        'game_id': '00000000-0000-0000-0000-0000000000aa',
        'state_version': 4,
        'phase': 'bidding',
        'own_hand': [
          {'suit': 'clubs', 'rank': 'ace'},
        ],
        'own_seat': 0,
        'own_bid': null,
        'own_tricks_won': 0,
        'own_avatar_id': 'face_01',
        'opponents': [
          for (var i = 0; i < names.length; i++)
            {
              'player_id': '00000000-0000-0000-0000-00000000000${i + 2}',
              'nickname': names[i],
              'seat': i + 1,
              'card_count': 1,
              'bid': i < 3 ? i + 1 : null,
              'tricks_won': 0,
              'connection_status': 'connected',
              'avatar_id': 'face_02',
            },
        ],
        'current_trick': <dynamic>[],
        'trump': 'spades',
        'current_turn': '00000000-0000-0000-0000-000000000005',
        'bids': [
          {'player_id': '00000000-0000-0000-0000-000000000002', 'bid': 1},
          {'player_id': '00000000-0000-0000-0000-000000000003', 'bid': 2},
          {'player_id': '00000000-0000-0000-0000-000000000004', 'bid': 3},
        ],
        'scores': <dynamic>[],
        'round': {
          'round_index': 0,
          'total_rounds': 3,
          'cards_per_player': 1,
          'dealer': _me,
          'tricks_completed': 0,
        },
        'legal_actions': {
          'legal_bids': <dynamic>[],
          'playable_cards': <dynamic>[],
        },
        'round_history': <dynamic>[],
      });

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

      expect(find.text('So far 6 / 1'), findsOneWidget);
      final recap = tester.getRect(find.text('So far 6 / 1'));
      final pills = [
        tester.getRect(find.text('P1 1')),
        tester.getRect(find.text('P2 2')),
        tester.getRect(find.text('P3 3')),
        tester.getRect(find.text('P4 —')),
        tester.getRect(find.text('you —')),
      ];
      for (final pill in pills) {
        expect(
          (pill.center.dy - recap.center.dy).abs(),
          lessThanOrEqualTo(8),
          reason: '8-max bidder roster must stay one line with So far',
        );
      }
      expect(
        pills.map((r) => r.bottom).reduce(math.max) -
            pills.map((r) => r.top).reduce(math.min),
        lessThanOrEqualTo(32),
      );
      expect(recap.height, lessThanOrEqualTo(24));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone 7-opponent table paints 2nd/3rd rails without moving 1st',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const names = [
        'Dharmendra Chaturvedi',
        'S2',
        'S3',
        'S4',
        'S5',
        'S6',
        'S7',
      ];
      const dharmendra = '00000000-0000-0000-0000-000000000002';
      const second = '00000000-0000-0000-0000-000000000003';
      const leader = '00000000-0000-0000-0000-000000000005';
      await _pump(
        tester,
        opponents: 7,
        names: names,
        myNickname: 'You',
        trickCount: 8,
        view: _playingView(
          opponents: 7,
          names: names,
          trickCount: 8,
          dealer: dharmendra,
          ladderRanks: const {dharmendra: 1},
          leader: const {'player_id': leader, 'margin': 20},
          scores: [
            {'player_id': leader, 'total_score': 50},
            {'player_id': dharmendra, 'total_score': 30},
            {'player_id': second, 'total_score': 30},
            {'player_id': _me, 'total_score': 8},
            {
              'player_id': '00000000-0000-0000-0000-000000000004',
              'total_score': 6,
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000006',
              'total_score': 4,
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000007',
              'total_score': 2,
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000008',
              'total_score': 1,
            },
          ],
          roundHistory: [
            {
              'round_index': 0,
              'entries': [
                {'player_id': leader, 'bid': 2, 'tricks_won': 2, 'score': 50},
              ],
            },
          ],
        ),
      );

      expect(find.text('👑'), findsOneWidget);
      expect(find.textContaining('ahead'), findsOneWidget);
      expect(find.textContaining('ahead on round scores'), findsNothing);
      final lead = tester.getRect(find.byKey(const ValueKey('table-lead-chip')));
      expect(lead.left, greaterThanOrEqualTo(0));
      expect(lead.right, lessThanOrEqualTo(390));
      expect(lead.top, greaterThanOrEqualTo(0));
      expect(lead.bottom, lessThanOrEqualTo(700));
      final trump = tester.getRect(find.byKey(const ValueKey('table-trump-face')));
      expect((lead.center.dy - trump.center.dy).abs(), lessThanOrEqualTo(8));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is TablePlaceRail && widget.place == 2,
        ),
        findsNWidgets(2),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is TablePlaceRail && widget.place == 3,
        ),
        findsNothing,
      );
      expect(find.text('b10·w10'), findsNWidgets(7));
      expect(find.text('D'), findsOneWidget);
      expect(find.byTooltip('1st overall'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final bid in tester.renderObjectList<RenderParagraph>(
        find.text('b10·w10'),
      )) {
        expect(bid.didExceedMaxLines, isFalse);
      }
    },
  );

  testWidgets(
    'self leader paints crown and own overall cap outside the chip clip',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const names = ['Gagan', 'Ankit S', 'Dharmendra C', 'ashish'];
      const second = '00000000-0000-0000-0000-000000000002';
      const third = '00000000-0000-0000-0000-000000000003';
      await _pump(
        tester,
        opponents: 4,
        names: names,
        myNickname: 'shobhit C',
        trickCount: 2,
        view: _playingView(
          opponents: 4,
          names: names,
          trickCount: 2,
          dealer: _me,
          ownLadderRank: 1,
          leader: const {'player_id': _me, 'margin': 12},
          scores: [
            {'player_id': _me, 'total_score': 40},
            {'player_id': second, 'total_score': 28},
            {'player_id': third, 'total_score': 20},
            {
              'player_id': '00000000-0000-0000-0000-000000000004',
              'total_score': 10,
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000005',
              'total_score': 4,
            },
          ],
          roundHistory: [
            {
              'round_index': 0,
              'entries': [
                {'player_id': _me, 'bid': 2, 'tricks_won': 2, 'score': 40},
              ],
            },
          ],
        ),
      );

      expect(find.text('👑'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.textContaining('ahead'), findsOneWidget);
      expect(find.textContaining('ahead on round scores'), findsNothing);
      expect(find.byTooltip('1st overall'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is TablePlaceRail && widget.place == 2,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is TablePlaceRail && widget.place == 3,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone lead chip keeps the margin on screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const leader = '00000000-0000-0000-0000-000000000002';
    const names = ['Dharmendra Chaturvedi', 'Ankit S', 'ashish'];
    await _pump(
      tester,
      opponents: 3,
      names: names,
      myNickname: 'shobhit C',
      view: _playingView(
        opponents: 3,
        names: names,
        dealer: leader,
        cardsPerPlayer: 3,
        leader: const {'player_id': leader, 'margin': 20},
        scores: [
          {'player_id': leader, 'total_score': 50},
          {'player_id': _me, 'total_score': 30},
          {
            'player_id': '00000000-0000-0000-0000-000000000003',
            'total_score': 20,
          },
          {
            'player_id': '00000000-0000-0000-0000-000000000004',
            'total_score': 10,
          },
        ],
        roundHistory: [
          {
            'round_index': 0,
            'entries': [
              {'player_id': leader, 'bid': 2, 'tricks_won': 2, 'score': 50},
            ],
          },
        ],
      ),
    );

    expect(find.text('D'), findsOneWidget);
    expect(find.text('👑'), findsOneWidget);
    expect(find.textContaining('+20'), findsOneWidget);
    expect(find.textContaining('ahead on round scores'), findsNothing);

    final chip = tester.getRect(find.byKey(const ValueKey('table-lead-chip')));
    expect(chip.left, greaterThanOrEqualTo(0));
    expect(chip.right, lessThanOrEqualTo(390));
    expect(chip.top, greaterThanOrEqualTo(0));
    expect(chip.bottom, lessThanOrEqualTo(700));
    final trump = tester.getRect(find.byKey(const ValueKey('table-trump-face')));
    expect((chip.center.dy - trump.center.dy).abs(), lessThanOrEqualTo(8));

    final margin = tester.widget<Text>(find.textContaining('+20'));
    expect(margin.style?.fontSize, greaterThanOrEqualTo(13));
    final marginPara = tester.renderObject<RenderParagraph>(
      find.textContaining('+20'),
    );
    expect(marginPara.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}
