import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';

const _me = '00000000-0000-0000-0000-000000000001';
const _guest = '00000000-0000-0000-0000-000000000002';
const _signed = '00000000-0000-0000-0000-000000000003';

PlayerGameView _view() {
  return PlayerGameView.fromJson({
    'game_id': '00000000-0000-0000-0000-0000000000aa',
    'state_version': 3,
    'phase': 'playing',
    'own_hand': <dynamic>[],
    'own_seat': 0,
    'own_bid': 1,
    'own_tricks_won': 0,
    'own_avatar_id': 'face_01',
    'own_signed_in': true,
    'opponents': [
      {
        'player_id': _guest,
        'nickname': 'Shobhit C',
        'seat': 1,
        'card_count': 3,
        'bid': 1,
        'tricks_won': 0,
        'connection_status': 'connected',
        'avatar_id': 'face_02',
      },
      {
        'player_id': _signed,
        'nickname': 'Gagan',
        'seat': 2,
        'card_count': 3,
        'bid': 0,
        'tricks_won': 1,
        'connection_status': 'connected',
        'avatar_id': 'face_03',
        'signed_in': true,
      },
    ],
    'current_trick': <dynamic>[],
    'trump': 'spades',
    'trump_card': {'suit': 'spades', 'rank': 'ace'},
    'current_turn': _me,
    'bids': <dynamic>[],
    'scores': <dynamic>[],
    'round': {
      'round_index': 0,
      'total_rounds': 12,
      'cards_per_player': 3,
      'dealer': _me,
      'tricks_completed': 0,
    },
    'legal_actions': {
      'legal_bids': <dynamic>[],
      'playable_cards': <dynamic>[],
    },
    'round_history': <dynamic>[],
  });
}

void main() {
  test('game view parses own and opponent signed_in', () {
    final view = _view();
    expect(view.ownSignedIn, isTrue);
    expect(
      view.opponents.singleWhere((o) => o.playerId == _guest).signedIn,
      isFalse,
    );
    expect(
      view.opponents.singleWhere((o) => o.playerId == _signed).signedIn,
      isTrue,
    );
  });

  testWidgets('table keeps signed-in checks on own and opponent seats', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = GameController(
      api: ApiClient(),
      gameId: '00000000-0000-0000-0000-0000000000aa',
      myPlayerId: _me,
      myNickname: 'Ankit',
    )..view = _view();

    await tester.pumpWidget(
      MaterialApp(
        home: TableScreen(controller: controller),
      ),
    );
    await tester.pump();

    final avatars = tester
        .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
        .toList();
    expect(
      avatars.where((a) => a.nickname == 'Ankit' && a.signedIn),
      isNotEmpty,
    );
    expect(
      avatars.where((a) => a.nickname == 'Gagan' && a.signedIn),
      isNotEmpty,
    );
    expect(
      avatars.where((a) => a.nickname == 'Shobhit C' && !a.signedIn),
      isNotEmpty,
    );
  });
}
