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
    tournamentListLoad = () async => const [];
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

  testWidgets('failed board load offers Try again and recovers', (
    tester,
  ) async {
    var calls = 0;
    leaderboardLoad = () async {
      calls += 1;
      if (calls == 1) {
        throw Exception('boom');
      }
      return const LeaderboardReport(players: []);
    };

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Couldn\'t load the board'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('No ranked games yet.'), findsOneWidget);
    expect(calls, 2);
  });
}
