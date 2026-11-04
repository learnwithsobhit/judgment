import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    leaderboardLoad = () async => const LeaderboardReport(players: []);
    fairPlayLeaderboardLoad = () async =>
        const FairPlayLeaderboardReport(players: []);
  });

  testWidgets('sheet switches between Top players and Fair play', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Gold 500, silver 100, bronze 20, then gold%, then bid%'),
      findsOneWidget,
    );
    expect(find.text('No ranked games yet.'), findsOneWidget);

    await tester.tap(find.text('Fair play').last);
    await tester.pumpAndSettle();

    expect(find.text('Highest average, then matches rated'), findsOneWidget);
    expect(find.text('No fair play ratings yet.'), findsOneWidget);
  });
}
