import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const feltGreen = Color(0xFF1B5E20);
const feltGreenDark = Color(0xFF0D3311);
const feltGreenMid = Color(0xFF2E7D32);
const woodBorder = Color(0xFF5D4037);
const goldAccent = Color(0xFFFFC857);
const suitRed = Color(0xFFFF6B6B);
const suitLight = Color(0xFFE8E8F0);

ThemeData buildTableGamesTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: feltGreen,
    brightness: Brightness.dark,
  ).copyWith(
    primary: goldAccent,
    onPrimary: feltGreenDark,
    surface: feltGreenDark,
  );

  final display = GoogleFonts.playfairDisplayTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );
  final body = GoogleFonts.sourceSans3TextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: feltGreenDark,
    textTheme: body.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        color: goldAccent,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: display.displayMedium?.copyWith(
        color: goldAccent,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        color: goldAccent,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        color: goldAccent,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: display.titleLarge?.copyWith(
        color: suitLight,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: goldAccent,
        foregroundColor: feltGreenDark,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: GoogleFonts.sourceSans3(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: goldAccent,
        side: const BorderSide(color: goldAccent),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
  );
}
