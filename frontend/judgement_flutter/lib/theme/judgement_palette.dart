import 'package:flutter/material.dart';

/// Felt, gold, and wood for the room. Cards, suits, and medals do not use this.
@immutable
class JudgementPalette extends ThemeExtension<JudgementPalette> {
  const JudgementPalette({
    required this.felt,
    required this.feltDark,
    required this.feltHighlight,
    required this.gold,
    required this.wood,
    required this.title,
  });

  final Color felt;
  final Color feltDark;
  final Color feltHighlight;
  final Color gold;
  final Color wood;
  final Color title;

  /// Same hexes as `feltGreen` / `feltGreenDark` / `goldAccent` in app.dart.
  static const off = JudgementPalette(
    felt: Color(0xFF1B5E20),
    feltDark: Color(0xFF0D3311),
    feltHighlight: Color(0xFF2E7D32),
    gold: Color(0xFFFFC857),
    wood: Color(0xFF5D4037),
    title: Color(0xFFFFC857),
  );

  static const diwali = JudgementPalette(
    felt: Color(0xFF4A1C2A),
    feltDark: Color(0xFF160910),
    feltHighlight: Color(0xFF6B2D3C),
    gold: Color(0xFFE8C36A),
    wood: Color(0xFF6B4A2A),
    title: Color(0xFFE8C36A),
  );

  static const christmas = JudgementPalette(
    felt: Color(0xFF0F3D2E),
    feltDark: Color(0xFF071A14),
    feltHighlight: Color(0xFF1B5C40),
    gold: Color(0xFFD4AF37),
    wood: Color(0xFF4A3020),
    title: Color(0xFFD4AF37),
  );

  static const holi = JudgementPalette(
    felt: Color(0xFF1B5E20),
    feltDark: Color(0xFF0D3311),
    feltHighlight: Color(0xFF2E7D32),
    gold: Color(0xFFFFC857),
    wood: Color(0xFF5D4037),
    title: Color(0xFFFFC857),
  );

  static const halloween = JudgementPalette(
    felt: Color(0xFF1A1A14),
    feltDark: Color(0xFF0C0C0A),
    feltHighlight: Color(0xFF2A2418),
    gold: Color(0xFFE09A3E),
    wood: Color(0xFF3D2A18),
    title: Color(0xFFE09A3E),
  );

  static const newYear = JudgementPalette(
    felt: Color(0xFF152038),
    feltDark: Color(0xFF0A101C),
    feltHighlight: Color(0xFF243656),
    gold: Color(0xFFF0D78C),
    wood: Color(0xFF3A3228),
    title: Color(0xFFF0D78C),
  );

  static const eid = JudgementPalette(
    felt: Color(0xFF134E3A),
    feltDark: Color(0xFF0A241C),
    feltHighlight: Color(0xFF1C6B4F),
    gold: Color(0xFFD4B45A),
    wood: Color(0xFF4A3A24),
    title: Color(0xFFD4B45A),
  );

  ThemeData get themeData {
    final scheme = ColorScheme.fromSeed(
      seedColor: felt,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: feltDark,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      extensions: <ThemeExtension<dynamic>>[this],
    );
  }

  @override
  JudgementPalette copyWith({
    Color? felt,
    Color? feltDark,
    Color? feltHighlight,
    Color? gold,
    Color? wood,
    Color? title,
  }) {
    return JudgementPalette(
      felt: felt ?? this.felt,
      feltDark: feltDark ?? this.feltDark,
      feltHighlight: feltHighlight ?? this.feltHighlight,
      gold: gold ?? this.gold,
      wood: wood ?? this.wood,
      title: title ?? this.title,
    );
  }

  @override
  JudgementPalette lerp(ThemeExtension<JudgementPalette>? other, double t) {
    if (other is! JudgementPalette) return this;
    return JudgementPalette(
      felt: Color.lerp(felt, other.felt, t)!,
      feltDark: Color.lerp(feltDark, other.feltDark, t)!,
      feltHighlight: Color.lerp(feltHighlight, other.feltHighlight, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      wood: Color.lerp(wood, other.wood, t)!,
      title: Color.lerp(title, other.title, t)!,
    );
  }
}

extension JudgementPaletteContext on BuildContext {
  JudgementPalette get palette =>
      Theme.of(this).extension<JudgementPalette>() ?? JudgementPalette.off;
}
