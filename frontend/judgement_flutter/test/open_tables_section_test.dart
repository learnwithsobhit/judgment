import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/open_tables_section.dart';

void main() {
  testWidgets('a waiting table fits above the fold on a phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenTablesSection(
            signedIn: true,
            tables: const [
              OpenTable(
                roomId: 'room-1',
                hostNickname: 'Upavan',
                seated: 2,
                maxPlayers: 6,
                seatsOpen: 4,
                withNames: ['Ankit', 'Gagan'],
                yours: true,
              ),
            ],
            onJoin: (_) {},
          ),
        ),
      ),
    );

    expect(find.text("You're at this table"), findsOneWidget);
    expect(find.text('Upavan'), findsOneWidget);
    expect(find.text('with Ankit and Gagan'), findsOneWidget);
    expect(find.text('2 of 6 seated, 4 open'), findsOneWidget);
    final open = tester.getRect(find.text('Open'));
    expect(open.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed out join explains how to see tables', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpenTablesSection(signedIn: false, tables: [], onJoin: _ignore),
        ),
      ),
    );
    expect(
      find.text('Sign in to see tables that are waiting.'),
      findsOneWidget,
    );
  });
}

void _ignore(OpenTable table) {}
