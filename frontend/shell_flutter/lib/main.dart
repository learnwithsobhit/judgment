import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:judgement_flutter/judgement_module.dart';
import 'package:judgement_flutter/util/room_share.dart';

import 'profile/shell_profile.dart';
import 'profile/shell_profile_store.dart';
import 'screens/home_screen.dart';
import 'state/pending_invite.dart';
import 'theme/table_games_theme.dart';
import 'widgets/whos_playing_sheet.dart';

void main() {
  // Required so /j/r/{CODE} in the address bar is seen by GoRouter
  // (otherwise Firebase serves index.html and the app boots at `/`).
  usePathUrlStrategy();
  runApp(const TableGamesApp());
}

/// Bootstrap path from the real browser URL (invite links, refresh).
String _locationFromBrowser() {
  final uri = Uri.base;
  var path = uri.path;
  if (path.endsWith('/index.html')) {
    path = path.substring(0, path.length - '/index.html'.length);
    if (path.isEmpty) path = '/';
  }
  if (path.isEmpty || path == '/') {
    final jRoom = uri.queryParameters['j_room'] ?? uri.queryParameters['room'];
    if (jRoom != null && jRoom.isNotEmpty) {
      final code = normalizeRoomCode(jRoom) ?? jRoom;
      return '/j/r/$code';
    }
    return '/';
  }
  return path;
}

final _router = GoRouter(
  initialLocation: _locationFromBrowser(),
  redirect: (context, state) {
    final path = state.uri.path;
    final q = state.uri.queryParameters;

    // Legacy / Safari query handoff.
    final jRoom = q['j_room'] ?? q['room'];
    if (jRoom != null &&
        jRoom.isNotEmpty &&
        !path.startsWith('/j/r/')) {
      final code = normalizeRoomCode(jRoom) ?? jRoom;
      return '/j/r/$code';
    }

    // Bare /r/CODE (old share shape) → embedded join path.
    final segments = state.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[0] == 'r') {
      final code = normalizeRoomCode(segments[1]);
      if (code != null) return '/j/r/$code';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/j',
      builder: (context, state) {
        final room = state.uri.queryParameters['room'] ??
            state.uri.queryParameters['j_room'];
        return _JudgementRoute(joinCode: room);
      },
    ),
    GoRoute(
      path: '/j/r/:code',
      builder: (context, state) {
        final raw = state.pathParameters['code'] ?? '';
        final code = normalizeRoomCode(raw.split('?').first);
        return _JudgementRoute(
          joinCode: code,
          invalidJoinLink: code == null,
        );
      },
    ),
  ],
);

class TableGamesApp extends StatelessWidget {
  const TableGamesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Table Games',
      debugShowCheckedModeBanner: false,
      theme: buildTableGamesTheme(),
      routerConfig: _router,
    );
  }
}

class _JudgementRoute extends StatefulWidget {
  final String? joinCode;
  final bool invalidJoinLink;

  const _JudgementRoute({
    this.joinCode,
    this.invalidJoinLink = false,
  });

  @override
  State<_JudgementRoute> createState() => _JudgementRouteState();
}

class _JudgementRouteState extends State<_JudgementRoute> {
  ShellProfile? _profile;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final isInvite =
        widget.joinCode != null && widget.joinCode!.trim().isNotEmpty;
    var profile = readShellProfile();

    if (isInvite && mounted) {
      // Invite joins must pick a guest nick — never silently reuse the host’s
      // saved profile from the same browser.
      profile = await showWhosPlayingSheet(
        context,
        initial: null,
        clearNickname: true,
        title: 'Who’s joining?',
        body: 'Enter your nickname for this table — not the host’s name.',
      );
      if (profile != null) {
        writeShellProfile(profile);
      }
    } else if (profile == null && mounted) {
      profile = await showWhosPlayingSheet(context);
      if (profile != null) {
        writeShellProfile(profile);
      }
    }

    if (!mounted) return;
    if (profile == null) {
      final code = widget.joinCode;
      if (code != null && code.isNotEmpty) {
        pendingJoinCode = code;
      }
      context.go('/');
      return;
    }
    pendingJoinCode = null;
    setState(() {
      _profile = profile;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final profile = _profile!;
    return JudgementModule(
      onExitToShell: () {
        pendingJoinCode = null;
        if (context.mounted) context.go('/');
      },
      initialJoinCode: widget.joinCode,
      invalidJoinLink: widget.invalidJoinLink,
      prefillNickname: profile.nickname,
      prefillAvatarId: profile.avatarId,
      sharePathPrefix: '/j',
    );
  }
}
