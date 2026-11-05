import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:judgement_flutter/networking/api_client.dart';
import 'package:judgement_flutter/util/avatar_pack.dart';
import 'package:judgement_flutter/util/photo_url.dart';
import 'package:judgement_flutter/widgets/avatar_picker.dart';
import 'package:judgement_flutter/widgets/player_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('client allow-list matches shared/avatar_allowlist.json', () {
    final file = File(
      '${Directory.current.path}/../../shared/avatar_allowlist.json',
    );
    expect(file.existsSync(), isTrue, reason: 'run tests from package root');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final imageIds = (json['image_ids'] as List).cast<String>();
    final legacyIds = (json['legacy_emoji_ids'] as List).cast<String>();
    expect(imageAvatarIds, imageIds);
    expect(legacyEmojiAvatarIds, legacyIds);
    expect({...allowedAvatarIds}, {...imageIds, ...legacyIds});
  });

  test('telegram portraits load through the API proxy', () {
    expect(
      displayPhotoUrl('https://cdn4.telesco.pe/file/abc'),
      '$apiBase/api/v1/photos?u=${Uri.encodeQueryComponent('https://cdn4.telesco.pe/file/abc')}',
    );
    expect(
      displayPhotoUrl('https://t.me/i/userpic/320/abc.jpg'),
      contains('/api/v1/photos?u='),
    );
    expect(
      displayPhotoUrl('https://lh3.googleusercontent.com/a/x'),
      'https://lh3.googleusercontent.com/a/x',
    );
    expect(displayPhotoUrl(null), isNull);
  });

  test('landing keeps a saved profile portrait', () {
    expect(isKeptAvatar(profileAvatarId), isTrue);
    expect(isKeptAvatar('face_01'), isTrue);
    expect(isKeptAvatar('not_a_face'), isFalse);
  });

  test('each image avatar has an asset file', () {
    for (final id in imageAvatarIds) {
      final path = 'assets/avatars/$id.png';
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(avatarAssetPath(id), path);
    }
  });

  testWidgets('PlayerAvatar renders image asset for face ids', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerAvatar(avatarId: 'face_01', nickname: 'Alex', radius: 24),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsOneWidget);
    // Image path is wired; AssetImage loads from bundle in widget tests via
    // flutter test asset resolution when pubspec lists the folder.
    final circle = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(circle.backgroundImage, isA<AssetImage>());
    expect(
      (circle.backgroundImage! as AssetImage).assetName,
      'assets/avatars/face_01.png',
    );
  });

  testWidgets('AvatarPicker exposes illustrated faces', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AvatarPicker(
              selectedId: 'face_01',
              onSelected: (id) => picked = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerAvatar), findsWidgets);
    await tester.tap(find.byType(InkWell).at(1));
    await tester.pumpAndSettle();
    expect(picked, 'face_02');
  });
}
