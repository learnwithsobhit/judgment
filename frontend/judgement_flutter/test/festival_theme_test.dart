import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/app/app.dart';
import 'package:judgement_flutter/auth/account_session.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/theme/festival_catalog.dart';
import 'package:judgement_flutter/theme/festival_controller.dart';
import 'package:judgement_flutter/theme/judgement_palette.dart';
import 'package:judgement_flutter/screens/lobby_screen.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/widgets/festival_admin_toggle.dart';
import 'package:judgement_flutter/widgets/festival_greeting_banner.dart';
import 'package:judgement_flutter/widgets/festive_overlay.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';
import 'package:judgement_flutter/widgets/live_games_card.dart';
import 'package:judgement_flutter/widgets/whos_free_card.dart';
import 'package:judgement_flutter/widgets/profile_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FestivalController.instance.resetForTest();
    festivalConfigLoad = () async => 'off';
    leaderboardLoad = () async => const LeaderboardReport(players: []);
    activeGamesLoad = () async => const [];
    availabilityLoad = () async =>
        const AvailabilityBoard(count: 0, ready: false, players: []);
    AccountSession.instance.isAdmin = false;
  });

  tearDown(() {
    FestivalController.instance.resetForTest();
    festivalConfigLoad = () => ApiClient().getConfig();
    festivalSet = (id) => adminFestivalClient().setFestival(id);
    leaderboardLoad = () => ApiClient().getLeaderboard();
    activeGamesLoad = () => ApiClient().getActiveGames();
    availabilityLoad = () => ApiClient().getAvailability();
    AccountSession.instance.isAdmin = false;
    AccountSession.instance.token = null;
  });

  test('off palette hexes match the classic felt constants', () {
    expect(FestivalTheme.off.palette.felt, feltGreen);
    expect(FestivalTheme.off.palette.feltDark, feltGreenDark);
    expect(FestivalTheme.off.palette.gold, goldAccent);
    expect(FestivalTheme.off.palette.title, goldAccent);
    expect(FestivalTheme.off.palette.feltHighlight, const Color(0xFF2E7D32));
    expect(FestivalTheme.off.palette.wood, const Color(0xFF5D4037));
  });

  test('unknown festival id falls back to off', () {
    expect(FestivalTheme.byId('songkran').id, 'off');
    expect(FestivalTheme.byId(null).id, 'off');
  });

  test('missing is_admin parses as false', () {
    final profile = MeProfile.fromJson({
      'user_id': 'u1',
      'display_name': 'Ada',
      'session_id': 's1',
      'nickname': 'Ada',
    });
    expect(profile.isAdmin, isFalse);
  });

  test('is_admin true is read loosely', () {
    final profile = MeProfile.fromJson({
      'user_id': 'u1',
      'display_name': 'Ada',
      'session_id': 's1',
      'nickname': 'Ada',
      'is_admin': true,
    });
    expect(profile.isAdmin, isTrue);
  });

  test('admin festival client carries the signed-in token', () {
    AccountSession.instance.token = 'session-token';
    expect(adminFestivalClient().token, 'session-token');
  });

  test(
    'config failure leaves the current theme and the account session',
    () async {
      AccountSession.instance.token = 'keep-me';
      FestivalController.instance.applyRemote('off');
      festivalConfigLoad = () async {
        throw ApiException(404, 'NOT_FOUND', 'missing');
      };
      await FestivalController.instance.refresh();
      expect(FestivalController.instance.festivalId, 'off');
      expect(AccountSession.instance.token, 'keep-me');
    },
  );

  test('play lock holds a remote id until the hand ends', () {
    final festive = FestivalController.instance;
    festive.setPlayLocked(true);
    festive.applyRemote('diwali');
    expect(festive.festivalId, 'off');
    festive.setPlayLocked(false);
    expect(festive.festivalId, 'diwali');
  });

  test('admin push applies even during a hand', () async {
    festivalSet = (id) async => id;
    final festive = FestivalController.instance;
    festive.setPlayLocked(true);
    await festive.pushFestival('diwali');
    expect(festive.festivalId, 'diwali');
  });

  testWidgets('festival notify does not pop the navigator', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const JudgementApp());
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('at the table')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('at the table'), findsOneWidget);

    FestivalController.instance.applyRemote('diwali');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('at the table'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('motif is IgnorePointer and off when calm', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FestivalHost(child: Scaffold(body: Text('home'))),
      ),
    );
    FestivalController.instance.applyRemote('diwali');
    await tester.pump();
    final overlay = find.byKey(const Key('festive-overlay'));
    expect(overlay, findsOneWidget);
    expect(
      find.descendant(of: overlay, matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );

    await FestivalController.instance.setCalm(true);
    await tester.pump();
    expect(
      find.descendant(of: overlay, matching: find.byType(IgnorePointer)),
      findsNothing,
    );
  });

  testWidgets('admin table look is hidden for a normal player', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AccountSession.instance.token = 'signed-in';
    AccountSession.instance.isAdmin = false;
    profileStatsLoad = () async => MeStats(
      displayName: 'Ada',
      gamesPlayed: 1,
      wins: 0,
      losses: 1,
      averageScore: 10,
      exactPercent: 50,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileSheet())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Table look'), findsNothing);
    expect(find.text('Choose festival'), findsNothing);
    expect(find.text('Hide festive motion'), findsOneWidget);
  });

  testWidgets('admin toggle sits at the top and turns festive off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    AccountSession.instance.isAdmin = true;
    festivalSet = (id) async => id;
    FestivalController.instance.applyRemote('diwali');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [FestivalAdminToggle(compact: true), Text('cards')],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(FestivalController.instance.festivalId, 'off');
    expect(find.text('Diwali'), findsNothing);
  });

  testWidgets('admin sees table look', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AccountSession.instance.token = 'signed-in';
    AccountSession.instance.isAdmin = true;
    profileStatsLoad = () async => MeStats(
      displayName: 'Shobhit',
      gamesPlayed: 1,
      wins: 1,
      losses: 0,
      averageScore: 20,
      exactPercent: 70,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileSheet())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Table look'), findsOneWidget);
    expect(find.text('Choose festival'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('admin profile actions stay on a phone screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    AccountSession.instance.token = 'signed-in';
    AccountSession.instance.isAdmin = true;
    profileStatsLoad = () async => MeStats(
      displayName: 'Shobhit',
      gamesPlayed: 103,
      wins: 24,
      losses: 79,
      averageScore: 87,
      exactPercent: 70,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const ProfileSheet(),
                );
              },
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    expect(find.text('Choose festival'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(
      tester.getRect(find.text('Sign out')).bottom,
      lessThanOrEqualTo(670),
    );
    expect(
      tester.getRect(find.text('Choose festival')).bottom,
      lessThan(tester.getRect(find.text('Sign out')).top),
    );
    await tester.tap(find.text('Choose festival'));
    await tester.pumpAndSettle();
    expect(find.text('Use this look'), findsOneWidget);
  });

  test('diwali greeting copy is a family wish', () {
    expect(FestivalTheme.off.greeting, isEmpty);
    expect(FestivalTheme.diwali.greeting, 'Happy Diwali');
    expect(
      FestivalTheme.diwali.wish,
      'Wishing you and your family light, luck, and exact bids.',
    );
    expect(FestivalTheme.eid.greeting, 'Eid Mubarak');
  });

  testWidgets('landing greeting shows for diwali and hides for classic', (
    tester,
  ) async {
    FestivalController.instance.applyRemote('diwali');
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [FestivalGreetingBanner(), Text('Create room')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Happy Diwali'), findsOneWidget);
    expect(
      find.text('Wishing you and your family light, luck, and exact bids.'),
      findsOneWidget,
    );
    expect(find.text('Create room'), findsOneWidget);

    FestivalController.instance.applyRemote('off');
    await tester.pump();
    expect(find.text('Happy Diwali'), findsNothing);
  });

  testWidgets('dismiss hides the greeting', (tester) async {
    FestivalController.instance.applyRemote('diwali');
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: FestivalGreetingBanner())),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Happy Diwali'), findsNothing);
    expect(FestivalController.instance.showGreeting, isFalse);
  });

  testWidgets('calm greeting has no sparkle', (tester) async {
    FestivalController.instance.applyRemote('diwali');
    await FestivalController.instance.setCalm(true);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FestivalGreetingBanner())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Happy Diwali'), findsOneWidget);
    expect(find.byKey(FestivalGreetingBanner.sparkleKey), findsNothing);
  });

  testWidgets('lobby shows the greeting above the room code', (tester) async {
    FestivalController.instance.applyRemote('diwali');
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: LobbyScreen(
            api: ApiClient(),
            nickname: 'Ankit',
            initialRoom: RoomView.fromJson({
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
                },
              ],
            }),
            myPlayerId: 'me',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Happy Diwali'), findsOneWidget);
    expect(find.text('AB3K9M'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Start game'), findsOneWidget);
  });

  testWidgets('greeting is not on FestivalHost or the live table', (
    tester,
  ) async {
    FestivalController.instance.applyRemote('diwali');
    FestivalController.instance.setPlayLocked(true);
    await tester.pumpWidget(
      const MaterialApp(
        home: FestivalHost(child: Scaffold(body: Text('felt'))),
      ),
    );
    await tester.pump();
    expect(find.text('Happy Diwali'), findsNothing);
    expect(find.byType(FestivalGreetingBanner), findsNothing);

    final controller = GameController(
      api: ApiClient(),
      gameId: '00000000-0000-0000-0000-0000000000aa',
      myPlayerId: '00000000-0000-0000-0000-000000000001',
      myNickname: 'Ada',
    );
    controller.view = PlayerGameView.fromJson({
      'game_id': '00000000-0000-0000-0000-0000000000aa',
      'state_version': 3,
      'phase': 'playing',
      'own_hand': <dynamic>[],
      'own_seat': 0,
      'own_bid': 1,
      'own_tricks_won': 0,
      'own_avatar_id': 'face_01',
      'opponents': [
        {
          'player_id': '00000000-0000-0000-0000-000000000002',
          'nickname': 'Ram',
          'seat': 1,
          'card_count': 3,
          'bid': 1,
          'tricks_won': 0,
          'connection_status': 'connected',
          'avatar_id': 'face_02',
        },
      ],
      'current_trick': <dynamic>[],
      'trump': 'spades',
      'trump_card': {'suit': 'spades', 'rank': 'ace'},
      'current_turn': '00000000-0000-0000-0000-000000000001',
      'bids': <dynamic>[],
      'scores': <dynamic>[],
      'round': {
        'round_index': 0,
        'total_rounds': 12,
        'cards_per_player': 3,
        'dealer': '00000000-0000-0000-0000-000000000001',
        'tricks_completed': 0,
      },
      'legal_actions': {
        'legal_bids': <dynamic>[],
        'playable_cards': <dynamic>[],
      },
      'round_history': <dynamic>[],
    });
    await tester.pumpWidget(
      MaterialApp(home: TableScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.text('Happy Diwali'), findsNothing);
    expect(find.byType(FestivalGreetingBanner), findsNothing);
  });
}
