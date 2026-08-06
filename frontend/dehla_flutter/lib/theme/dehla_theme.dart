import 'package:flutter/material.dart';

const feltGreen = Color(0xFF1B5E20);
const feltGreenDark = Color(0xFF0D3311);
const goldAccent = Color(0xFFFFC857);

/// Partnership ring for internal team `a` (seats 0 & 2).
const teamRingWarm = Color(0xFFF4A261);

/// Partnership ring for internal team `b` (seats 1 & 3).
const teamRingCool = Color(0xFF4ECDC4);

/// Avatar ring color for protocol team id (`a` / `b`). Null when unknown.
Color? teamRingFor(String? team) {
  switch (team?.toLowerCase()) {
    case 'a':
      return teamRingWarm;
    case 'b':
      return teamRingCool;
    default:
      return null;
  }
}

/// Short spoken label for accessibility / result copy (not used on seat chips).
String teamSideLabel(String? team) {
  switch (team?.toLowerCase()) {
    case 'a':
      return 'Warm';
    case 'b':
      return 'Teal';
    default:
      return 'Unknown';
  }
}

ThemeData buildDehlaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: feltGreen,
    brightness: Brightness.dark,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: feltGreenDark,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
  );
}

Color suitColor(String? suit) {
  switch (suit) {
    case 'hearts':
    case 'diamonds':
      return const Color(0xFFFF6B6B);
    default:
      return const Color(0xFFE8E8F0);
  }
}

Color suitColorOnLight(String? suit) {
  switch (suit) {
    case 'hearts':
    case 'diamonds':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF1A1A2E);
  }
}
