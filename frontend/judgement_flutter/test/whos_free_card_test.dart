import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/widgets/whos_free_card.dart';

AvailabilityBoard boardOf(List<String> names, {String? myUserId}) {
  return AvailabilityBoard(
    count: names.length,
    ready: names.length >= 3,
    players: [
      for (var i = 0; i < names.length; i++)
        AvailabilityPlayer(
          userId: myUserId != null && i == 0 ? myUserId : 'u$i',
          displayName: names[i],
          avatarId: 'face_01',
          availableUntil: DateTime.utc(2026, 11, 9, 12),
        ),
    ],
  );
}

Future<void> pumpCard(
  WidgetTester tester,
  WhosFreeCard card, {
  double width = 360,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0D3311),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: card,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty board keeps the switch for a signed-in player', (
    tester,
  ) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const []),
        signedIn: true,
        myUserId: 'me',
        onToggle: (_) {},
      ),
    );

    expect(find.text('WHO\'S FREE'), findsOneWidget);
    expect(find.text('No one is free yet.'), findsOneWidget);
    expect(find.text('I\'m free'), findsOneWidget);
    expect(find.text('For the next 90 minutes.'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('one player needs two more', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const ['Ada']),
        signedIn: true,
        myUserId: 'me',
        onToggle: (_) {},
      ),
    );
    expect(find.text('Need 2 more.'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Ready to play.'), findsNothing);
  });

  testWidgets('two players need one more', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const ['Ada', 'Grace']),
        signedIn: true,
        myUserId: 'me',
        onToggle: (_) {},
      ),
    );
    expect(find.text('Need 1 more.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start a table'), findsNothing);
  });

  testWidgets('three players show the gold ready state', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const ['Ada', 'Grace', 'Beena']),
        signedIn: true,
        myUserId: 'me',
        onToggle: (_) {},
        onStartTable: () {},
      ),
    );
    expect(find.text('Ready to play.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start a table'), findsOneWidget);
    expect(find.textContaining('Need'), findsNothing);
  });

  testWidgets('a guest sees the list with no switch', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(board: boardOf(const ['Ada']), signedIn: false),
    );
    expect(find.text('Sign in to mark yourself free.'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('I\'m free'), findsNothing);
  });

  testWidgets('a failed save leaves the switch unchanged', (tester) async {
    var taps = 0;
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const []),
        signedIn: true,
        myUserId: 'me',
        saveError: 'Couldn\'t update. Try again.',
        onToggle: (_) => taps += 1,
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(taps, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Couldn\'t update. Try again.'), findsOneWidget);
  });

  testWidgets('names stay on one line', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const ['Ankit Sunil Chaturvedi']),
        signedIn: false,
      ),
    );
    final name = tester.widget<Text>(find.text('Ankit Sunil Chaturvedi'));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
  });

  testWidgets('own seat reads You', (tester) async {
    await pumpCard(
      tester,
      WhosFreeCard(
        board: boardOf(const ['Ada'], myUserId: 'me'),
        signedIn: true,
        myUserId: 'me',
        onToggle: (_) {},
      ),
    );
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
    expect(find.text('For the next 90 minutes.'), findsOneWidget);
  });
}
