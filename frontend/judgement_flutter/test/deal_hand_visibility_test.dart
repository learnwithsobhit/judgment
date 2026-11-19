import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';

const _me = '00000000-0000-0000-0000-000000000001';
const _opp = '00000000-0000-0000-0000-000000000002';

void _mockAudioplayers() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (_) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (_) async => null,
  );
}

Map<String, dynamic> _baseViewJson({
  required String phase,
  required List<dynamic> ownHand,
  Map<String, dynamic>? shuffle,
  List<dynamic>? legalBids,
}) {
  return {
    'game_id': '00000000-0000-0000-0000-0000000000aa',
    'state_version': shuffle == null ? 5 : 4,
    'phase': phase,
    'own_hand': ownHand,
    'own_seat': 0,
    'own_bid': null,
    'own_tricks_won': 0,
    'own_avatar_id': 'face_01',
    'opponents': [
      {
        'player_id': _opp,
        'nickname': 'Peer',
        'seat': 1,
        'card_count': ownHand.isEmpty ? 0 : ownHand.length,
        'bid': null,
        'tricks_won': 0,
        'connection_status': 'connected',
        'avatar_id': 'face_02',
      },
    ],
    'current_trick': <dynamic>[],
    'trump': null,
    'trump_card': null,
    'current_turn': _me,
    'bids': <dynamic>[],
    'scores': <dynamic>[],
    'round': {
      'round_index': 0,
      'total_rounds': 12,
      'cards_per_player': ownHand.isEmpty ? 0 : ownHand.length,
      'dealer': _me,
      'tricks_completed': 0,
    },
    'legal_actions': {
      'legal_bids': legalBids ?? [0, 1, 2],
      'playable_cards': <dynamic>[],
    },
    'round_history': <dynamic>[],
    if (shuffle != null) 'shuffle': shuffle,
  };
}

PlayerGameView _ritualView() {
  return PlayerGameView.fromJson(
    _baseViewJson(
      phase: 'dealing',
      ownHand: const [],
      shuffle: {
        'shuffle_index': 1,
        'animation_seed': 42,
        'can_shuffle': false,
        'can_deal': true,
      },
    ),
  );
}

PlayerGameView _biddingView({required List<Map<String, dynamic>> hand}) {
  return PlayerGameView.fromJson(
    _baseViewJson(
      phase: 'bidding',
      ownHand: hand,
      legalBids: [0, 1, 2, 3],
    ),
  );
}

const _sampleHand = [
  {'suit': 'spades', 'rank': 'ace'},
  {'suit': 'hearts', 'rank': 'king'},
  {'suit': 'clubs', 'rank': 'two'},
];

GameController _controller() {
  final controller = GameController(
    api: ApiClient(baseUrl: 'http://127.0.0.1:9'),
    gameId: '00000000-0000-0000-0000-0000000000aa',
    myPlayerId: _me,
    myNickname: 'Me',
  );
  controller.debugSkipNetworkConnect = true;
  controller.debugMarkConnected();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockAudioplayers);

  testWidgets('ritual to bidding keeps hand without a hide window', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.debugHandleMessage(StateSnapshot(view: _ritualView()));
    expect(controller.view!.isShuffleRitual, isTrue);
    expect(controller.view!.ownHand, isEmpty);

    controller.debugHandleMessage(
      StateSnapshot(view: _biddingView(hand: _sampleHand)),
    );
    expect(controller.view!.phase, 'bidding');
    expect(controller.view!.ownHand, hasLength(3));
    expect(controller.isMyTurn, isTrue);
  });

  testWidgets('first snapshot as bidding (reconnect / prev null) shows hand', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    expect(controller.view, isNull);
    controller.debugHandleMessage(
      StateSnapshot(view: _biddingView(hand: _sampleHand)),
    );
    expect(controller.view!.ownHand, hasLength(3));
    expect(controller.view!.phase, 'bidding');
  });

  testWidgets('table renders hand cards after ritual to bidding', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller();
    controller.debugHandleMessage(StateSnapshot(view: _ritualView()));

    await tester.pumpWidget(
      MaterialApp(home: TableScreen(controller: controller)),
    );
    await tester.pump();

    controller.debugHandleMessage(
      StateSnapshot(view: _biddingView(hand: _sampleHand)),
    );
    await tester.pump();

    expect(find.byType(PlayingCardWidget), findsNWidgets(3));
    expect(find.bySemanticsLabel('ace of spades'), findsOneWidget);
    expect(find.bySemanticsLabel('king of hearts'), findsOneWidget);
    expect(find.bySemanticsLabel('two of clubs'), findsOneWidget);

    semantics.dispose();
    // TableScreen.dispose owns the controller.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduce-motion still shows hand cards immediately', (
    tester,
  ) async {
    final controller = _controller();
    controller.debugHandleMessage(
      StateSnapshot(view: _biddingView(hand: _sampleHand)),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: TableScreen(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byType(PlayingCardWidget), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
