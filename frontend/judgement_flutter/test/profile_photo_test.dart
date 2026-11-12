import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/models/protocol.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/screens/fair_play_screen.dart';
import 'package:judgement_flutter/screens/table_screen.dart';
import 'package:judgement_flutter/state/game_controller.dart';
import 'package:judgement_flutter/util/avatar_pack.dart';
import 'package:judgement_flutter/widgets/avatar_picker.dart';
import 'package:judgement_flutter/widgets/latest_game_card.dart';
import 'package:judgement_flutter/widgets/leaderboard_sheet.dart';
import 'package:judgement_flutter/widgets/live_games_card.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _photo = 'https://lh3.googleusercontent.com/a/test-photo';

void _useMemoryPhoto() {
  debugProfilePhotoProvider = (_) => const _OkPhoto();
}

void _useFailingPhoto() {
  debugProfilePhotoProvider = (_) => const _FailingPhoto();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _useMemoryPhoto();
  });

  tearDown(() {
    debugProfilePhotoProvider = null;
  });

  testWidgets('guests keep the face grid without a photo row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarPicker(selectedId: 'face_01', onSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Your avatar'), findsOneWidget);
    expect(find.text('Use my photo'), findsNothing);
    expect(find.text('Or pick a character'), findsNothing);
  });

  testWidgets('Use my photo row sits above the face grid', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarPicker(
              selectedId: 'face_01',
              photoUrl: _photo,
              nickname: 'Ada',
              onSelected: (id) => picked = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Use my photo'), findsOneWidget);
    expect(find.text('Or pick a character'), findsOneWidget);
    expect(find.text('Tap to use your photo instead.'), findsOneWidget);
    expect(find.text('Your avatar'), findsNothing);

    await tester.tap(find.text('Use my photo'));
    await tester.pumpAndSettle();
    expect(picked, profileAvatarId);
  });

  testWidgets('a failed photo stays unselected and keeps the letter', (
    tester,
  ) async {
    _useFailingPhoto();
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarPicker(
              selectedId: 'face_07',
              photoUrl: _photo,
              nickname: 'Ada',
              onSelected: (id) => picked = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Photo didn’t load. Pick a character for now.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use my photo'));
    await tester.pumpAndSettle();
    expect(picked, isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerAvatar(
            avatarId: profileAvatarId,
            photoUrl: _photo,
            nickname: 'Ada',
            radius: 20,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('save profile only after the image paints', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarPicker(
              selectedId: 'face_01',
              photoUrl: _photo,
              nickname: 'Ada',
              autoSelectProfile: true,
              onSelected: (id) => picked = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(picked, profileAvatarId);
  });

  testWidgets('the same profile portrait paints on every public surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller =
        GameController(
            api: ApiClient(),
            gameId: 'g1',
            myPlayerId: 'me',
            myNickname: 'Ada',
          )
          ..view = PlayerGameView.fromJson({
            'game_id': 'g1',
            'state_version': 1,
            'phase': 'playing',
            'own_hand': <dynamic>[],
            'own_seat': 0,
            'own_bid': 1,
            'own_tricks_won': 0,
            'own_avatar_id': profileAvatarId,
            'own_photo_url': _photo,
            'own_signed_in': true,
            'opponents': [
              {
                'player_id': 'p2',
                'nickname': 'Beena',
                'seat': 1,
                'card_count': 1,
                'bid': 0,
                'tricks_won': 0,
                'connection_status': 'connected',
                'avatar_id': profileAvatarId,
                'photo_url': _photo,
                'signed_in': true,
              },
            ],
            'current_trick': <dynamic>[],
            'trump': 'spades',
            'current_turn': 'me',
            'bids': <dynamic>[],
            'scores': <dynamic>[],
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
    _expectProfile(tester, find.byType(TableScreen));

    final report = LeaderboardReport(
      players: const [
        LeaderboardEntry(
          rank: 1,
          displayName: 'Ada',
          avatarId: profileAvatarId,
          photoUrl: _photo,
          wins: 1,
          games: 1,
          exactPercent: 0,
          averageScore: 0,
        ),
      ],
      latestGame: LatestGame(
        gameId: 'g1',
        finishedAt: DateTime.utc(2026, 10, 30),
        tableSize: 3,
        roundsPlayed: 8,
        seats: const [
          LatestGameSeat(
            userId: 'u1',
            displayName: 'Ada',
            avatarId: profileAvatarId,
            photoUrl: _photo,
            finishRank: 1,
            totalScore: 40,
            exactBidRounds: 2,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LatestGameCard(report: report)),
      ),
    );
    await tester.pump();
    _expectProfile(tester, find.byType(LatestGameCard));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveGamesCard(
            games: [
              ActiveGame(
                gameId: 'live-1',
                updatedAt: DateTime.utc(2026, 10, 30),
                roundIndex: 1,
                totalRounds: 12,
                phase: 'bidding',
                seats: const [
                  ActiveGameSeat(
                    displayName: 'Ada',
                    avatarId: profileAvatarId,
                    photoUrl: _photo,
                    totalScore: 10,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    _expectProfile(tester, find.byType(LiveGamesCard));

    leaderboardLoad = () async => report;
    tournamentListLoad = () async => const [];
    fairPlayLeaderboardLoad = () async => FairPlayLeaderboardReport(
      players: [
        FairPlayLeaderboardEntry(
          rank: 1,
          displayName: 'Ada',
          avatarId: profileAvatarId,
          photoUrl: _photo,
          pointsReceived: 10,
          ratingsReceived: 1,
          gamesRated: 1,
          average: 10,
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardSheet())),
    );
    await tester.pumpAndSettle();
    _expectProfile(tester, find.byType(LeaderboardSheet));

    await tester.tap(find.text('Fair play').last);
    await tester.pumpAndSettle();
    _expectProfile(tester, find.byType(LeaderboardSheet));

    final api = _FairPlayApi(
      FairPlayGameView(
        canVote: true,
        alreadySubmitted: false,
        ratees: [
          FairPlayRatee(
            userId: 'b',
            displayName: 'Beena',
            avatarId: profileAvatarId,
            photoUrl: _photo,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FairPlayScreen(api: api, gameId: 'g1', onContinue: () {}),
      ),
    );
    await tester.pumpAndSettle();
    _expectProfile(tester, find.byType(FairPlayScreen));
  });
}

void _expectProfile(WidgetTester tester, Finder scope) {
  final avatars = tester
      .widgetList<PlayerAvatar>(
        find.descendant(of: scope, matching: find.byType(PlayerAvatar)),
      )
      .where((avatar) => avatar.avatarId == profileAvatarId)
      .toList();
  expect(avatars, isNotEmpty);
  expect(avatars.every((avatar) => avatar.photoUrl == _photo), isTrue);
}

class _FairPlayApi extends ApiClient {
  _FairPlayApi(this.view);

  final FairPlayGameView view;

  @override
  Future<FairPlayGameView> getFairPlay(String gameId) async => view;

  @override
  Future<FairPlayGameView> submitFairPlay(
    String gameId,
    List<({String userId, int points})> ratings,
  ) async => view;
}

class _OkPhoto extends ImageProvider<_OkPhoto> {
  const _OkPhoto();

  @override
  Future<_OkPhoto> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_OkPhoto key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_solidFrame());
  }
}

Future<ImageInfo> _solidFrame() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(1, 1);
  return ImageInfo(image: image);
}

class _FailingPhoto extends ImageProvider<_FailingPhoto> {
  const _FailingPhoto();

  @override
  Future<_FailingPhoto> obtainKey(ImageConfiguration configuration) async =>
      this;

  @override
  ImageStreamCompleter loadImage(
    _FailingPhoto key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(Exception('photo failed')),
    );
  }
}
