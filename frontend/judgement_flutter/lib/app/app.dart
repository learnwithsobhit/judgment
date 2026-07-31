import 'package:flutter/material.dart';

import '../networking/api_client.dart';
import '../screens/event_invite_screen.dart';
import '../screens/event_manage_screen.dart';
import '../screens/landing_screen.dart';

const feltGreen = Color(0xFF1B5E20);
const feltGreenDark = Color(0xFF0D3311);
const goldAccent = Color(0xFFFFC857);

/// Parse `/e/{slug}` and `/e/{slug}/manage?token=` from the browser URL.
Widget initialHomeFromUri(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length >= 2 && segments[0] == 'e') {
    final slug = segments[1];
    if (segments.length >= 3 && segments[2] == 'manage') {
      final token = uri.queryParameters['token'] ?? '';
      if (token.isNotEmpty) {
        return EventManageScreen(
          api: ApiClient(),
          slug: slug,
          manageToken: token,
          nickname: 'Host',
        );
      }
    }
    return EventInviteScreen(slug: slug);
  }
  return const LandingScreen();
}

class JudgementApp extends StatelessWidget {
  final Widget? home;

  const JudgementApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: feltGreen,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Judgement',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: feltGreenDark,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      ),
      home: home ?? initialHomeFromUri(Uri.base),
    );
  }
}
