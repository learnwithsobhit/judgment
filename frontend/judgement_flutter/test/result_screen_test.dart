import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/result_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';

PlayerGameView _finishedView() {
  return PlayerGameView.fromJson({
    'game_id': '00000000-0000-0000-0000-000000000001',
    'state_version': 500,
    'phase': 'finished',
    'own_hand': <dynamic>[],
    'own_seat': 0,
    'own_bid': null,
    'own_tricks_won': 0,
    'own_avatar_id': 'fox',
    'opponents': [
      {
        'player_id': '00000000-0000-0000-0000-000000000002',
        'nickname': 'Beth',
        'seat': 1,
        'card_count': 0,
        'bid': null,
        'tricks_won': 0,
        'connection_status': 'connected',
        'avatar_id': 'owl',
      },
      {
        'player_id': '00000000-0000-0000-0000-000000000003',
        'nickname': 'Chris',
        'seat': 2,
        'card_count': 0,
        'bid': null,
        'tricks_won': 0,
        'connection_status': 'connected',
        'avatar_id': 'bear',
      },
    ],
    'current_trick': <dynamic>[],
    'trump': null,
    'trump_card': null,
    'current_turn': null,
    'bids': <dynamic>[],
    'scores': <dynamic>[],
    'round': null,
    'legal_actions': {
      'legal_bids': <dynamic>[],
      'playable_cards': <dynamic>[],
    },
    'final_ranking': [
      {
        'player_id': '00000000-0000-0000-0000-000000000002',
        'rank': 1,
        'total_score': 40,
        'exact_bid_rounds': 3,
        'total_tricks_missed': 1,
      },
      {
        'player_id': '00000000-0000-0000-0000-000000000001',
        'rank': 2,
        'total_score': 30,
        'exact_bid_rounds': 2,
        'total_tricks_missed': 2,
      },
      {
        'player_id': '00000000-0000-0000-0000-000000000003',
        'rank': 3,
        'total_score': 20,
        'exact_bid_rounds': 1,
        'total_tricks_missed': 4,
      },
    ],
    'round_history': [
      {
        'round_index': 0,
        'entries': [
          {
            'player_id': '00000000-0000-0000-0000-000000000001',
            'bid': 1,
            'tricks_won': 1,
            'score': 11,
          },
          {
            'player_id': '00000000-0000-0000-0000-000000000002',
            'bid': 0,
            'tricks_won': 0,
            'score': 10,
          },
          {
            'player_id': '00000000-0000-0000-0000-000000000003',
            'bid': 1,
            'tricks_won': 0,
            'score': 0,
          },
        ],
      },
      {
        'round_index': 1,
        'entries': [
          {
            'player_id': '00000000-0000-0000-0000-000000000001',
            'bid': 1,
            'tricks_won': 0,
            'score': 0,
          },
          {
            'player_id': '00000000-0000-0000-0000-000000000002',
            'bid': 2,
            'tricks_won': 2,
            'score': 12,
          },
          {
            'player_id': '00000000-0000-0000-0000-000000000003',
            'bid': 0,
            'tricks_won': 0,
            'score': 10,
          },
        ],
      },
    ],
  });
}

void main() {
  testWidgets('results show podium/standings without coaching', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = GameController(
      api: ApiClient(),
      gameId: '00000000-0000-0000-0000-000000000001',
      myPlayerId: '00000000-0000-0000-0000-000000000001',
      myNickname: 'Alex',
    );
    controller.view = _finishedView();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: feltGreen,
            brightness: Brightness.dark,
          ),
        ),
        home: ResultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your coach'), findsNothing);
    expect(find.textContaining('Beth wins'), findsOneWidget);
    expect(find.text('You placed #2'), findsOneWidget);
    expect(find.text('Final standings'), findsOneWidget);
    expect(find.text('Your night'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy results summary'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
  });
}
