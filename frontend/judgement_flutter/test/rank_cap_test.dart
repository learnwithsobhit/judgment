import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';
import 'package:judgement_flutter/widgets/playing_card.dart';

void main() {
  testWidgets('overall cap sits on the portrait without growing the seat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<Size> avatarSize(int? rank) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: PlayerAvatar(
              avatarId: 'face_28',
              nickname: 'Upavan',
              radius: 20,
              boardRank: rank,
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(PlayerAvatar));
    }

    final plain = await avatarSize(null);
    final capped = await avatarSize(1);
    expect(capped, plain);
    expect(find.byTooltip('1st overall'), findsOneWidget);
    expect(find.byTooltip('2nd overall'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 70,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const PlayerAvatar(
                      avatarId: 'face_28',
                      nickname: 'Upavan',
                      radius: 16,
                      highlight: true,
                      boardRank: 1,
                    ),
                    const Positioned(
                      right: -2,
                      top: -2,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: goldAccent,
                        child: Text(
                          'D',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: -2,
                      top: -2,
                      child: Text('👑', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
                const Text('Upavan'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('1st overall'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('👑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('silver and bronze caps name their place', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            PlayerAvatar(
              avatarId: 'face_20',
              nickname: 'Dharmendra',
              boardRank: 2,
            ),
            PlayerAvatar(avatarId: 'face_10', nickname: 'Ankit', boardRank: 3),
            PlayerAvatar(avatarId: 'face_01', nickname: 'Guest', boardRank: 4),
          ],
        ),
      ),
    );

    expect(find.byTooltip('2nd overall'), findsOneWidget);
    expect(find.byTooltip('3rd overall'), findsOneWidget);
    expect(find.byTooltip('1st overall'), findsNothing);
  });

  testWidgets(
    'a phone-width table keeps the cap, dealer, crown, and card size',
    (tester) async {
      const me = '00000000-0000-0000-0000-000000000001';
      const leader = '00000000-0000-0000-0000-000000000002';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      Future<double> handWidth({int? ownRank, int? leaderRank}) async {
        final controller = GameController(
          api: ApiClient(),
          gameId: '00000000-0000-0000-0000-0000000000aa',
          myPlayerId: me,
          myNickname: 'Ankit',
        );
        controller.view = PlayerGameView.fromJson({
          'game_id': '00000000-0000-0000-0000-0000000000aa',
          'state_version': 4,
          'phase': 'playing',
          'own_hand': [
            {'suit': 'hearts', 'rank': 'ace'},
            {'suit': 'spades', 'rank': 'king'},
            {'suit': 'clubs', 'rank': 'queen'},
            {'suit': 'diamonds', 'rank': 'jack'},
          ],
          'own_seat': 0,
          'own_bid': 1,
          'own_tricks_won': 0,
          'own_avatar_id': 'face_10',
          'own_ladder_rank': ?ownRank,
          'opponents': [
            {
              'player_id': leader,
              'nickname': 'Upavan',
              'seat': 1,
              'card_count': 4,
              'bid': 2,
              'tricks_won': 1,
              'connection_status': 'connected',
              'avatar_id': 'face_28',
              'ladder_rank': ?leaderRank,
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000003',
              'nickname': 'Guest',
              'seat': 2,
              'card_count': 4,
              'bid': 1,
              'tricks_won': 0,
              'connection_status': 'connected',
              'avatar_id': 'face_01',
            },
            {
              'player_id': '00000000-0000-0000-0000-000000000004',
              'nickname': 'Right',
              'seat': 3,
              'card_count': 4,
              'bid': 1,
              'tricks_won': 0,
              'connection_status': 'connected',
              'avatar_id': 'face_02',
            },
          ],
          'current_trick': <dynamic>[],
          'trump': 'hearts',
          'current_turn': leader,
          'bids': <dynamic>[],
          'scores': <dynamic>[],
          'leader': {'player_id': leader, 'margin': 8},
          'round': {
            'round_index': 0,
            'total_rounds': 12,
            'cards_per_player': 4,
            'dealer': leader,
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
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(PlayingCardWidget).first).width;
      }

      final plain = await handWidth();
      final capped = await handWidth(ownRank: 2, leaderRank: 1);

      expect(plain, 52);
      expect(capped, plain);
      expect(find.byTooltip('1st overall'), findsOneWidget);
      expect(find.byTooltip('2nd overall'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
