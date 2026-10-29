import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/lobby_screen.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';

void main() {
  test('seat signed_in defaults false when omitted', () {
    final seat = SeatView.fromJson({
      'player_id': 'p1',
      'nickname': 'Ada',
      'seat': 0,
      'ready': false,
      'is_host': true,
    });
    expect(seat.signedIn, isFalse);
  });

  test('seat signed_in parses true', () {
    final seat = SeatView.fromJson({
      'player_id': 'p1',
      'nickname': 'Ada',
      'seat': 0,
      'ready': false,
      'is_host': true,
      'signed_in': true,
    });
    expect(seat.signedIn, isTrue);
  });

  testWidgets('lobby shows a check for signed-in and Guest for guests', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final room = RoomView.fromJson({
      'room_id': 'room-1',
      'code': 'AB3K9M',
      'phase': 'lobby',
      'max_players': 4,
      'min_players': 3,
      'round_schedule_summary': 'Automatic',
      'seats': [
        {
          'player_id': 'me',
          'nickname': 'Ankit',
          'seat': 0,
          'ready': false,
          'is_host': true,
          'signed_in': true,
        },
        {
          'player_id': 'p2',
          'nickname': 'Shobhit C',
          'seat': 1,
          'ready': true,
          'is_host': false,
          'signed_in': false,
        },
        {
          'player_id': 'p3',
          'nickname': 'Gagan',
          'seat': 2,
          'ready': true,
          'is_host': false,
          'signed_in': true,
        },
      ],
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

    expect(
      find.text(
        'A check means the seat is signed in. '
        'Guest seats do not count on Top players.',
      ),
      findsOneWidget,
    );
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Shobhit C'), findsOneWidget);
    expect(find.byTooltip('Signed in'), findsNWidgets(2));

    final seatAvatars = tester
        .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
        .where(
          (a) =>
              a.nickname == 'Ankit' ||
              a.nickname == 'Shobhit C' ||
              a.nickname == 'Gagan',
        )
        .toList();
    expect(seatAvatars.length, 3);
    expect(
      seatAvatars.where((a) => a.nickname == 'Ankit' && a.signedIn),
      isNotEmpty,
    );
    expect(
      seatAvatars.where((a) => a.nickname == 'Gagan' && a.signedIn),
      isNotEmpty,
    );
    expect(
      seatAvatars.where((a) => a.nickname == 'Shobhit C' && !a.signedIn),
      isNotEmpty,
    );

    // Account badge is a check chip, not a green/red online ring.
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
