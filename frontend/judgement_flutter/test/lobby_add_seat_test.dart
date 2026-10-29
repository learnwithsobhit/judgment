import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/lobby_screen.dart';

RoomView _room({required int maxPlayers, required bool host}) {
  return RoomView.fromJson({
    'room_id': 'room-1',
    'code': 'AB3K9M',
    'phase': 'lobby',
    'max_players': maxPlayers,
    'min_players': 3,
    'round_schedule_summary': 'Automatic',
    'seats': [
      {
        'player_id': 'me',
        'nickname': 'Ankit',
        'seat': 0,
        'ready': false,
        'is_host': host,
      },
      {
        'player_id': 'p2',
        'nickname': 'Beena',
        'seat': 1,
        'ready': true,
        'is_host': false,
      },
      {
        'player_id': 'p3',
        'nickname': 'Gagan',
        'seat': 2,
        'ready': true,
        'is_host': false,
      },
      {
        'player_id': 'p4',
        'nickname': 'Upavan',
        'seat': 3,
        'ready': true,
        'is_host': false,
      },
    ],
  });
}

Future<void> _pump(WidgetTester tester, RoomView room) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 700);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: LobbyScreen(
        api: ApiClient(),
        nickname: 'Ankit',
        initialRoom: room,
        myPlayerId: 'me',
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the host can add a seat on a phone', (tester) async {
    await _pump(tester, _room(maxPlayers: 4, host: true));

    expect(find.text('Players 4 / 4'), findsOneWidget);
    expect(find.text('Add a seat'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Start game'), findsOneWidget);
    final add = tester.getRect(find.text('Add a seat'));
    expect(add.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('other players and a full table of 8 have no add control', (
    tester,
  ) async {
    await _pump(tester, _room(maxPlayers: 4, host: false));
    expect(find.text('Add a seat'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, _room(maxPlayers: 8, host: true));
    expect(find.text('Add a seat'), findsNothing);
    expect(find.text('Players 4 / 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
