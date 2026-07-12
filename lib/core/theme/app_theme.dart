import 'package:flutter/material.dart';

/// Design-Tokens – Single Source of Truth für die Marke "Wickelfinder".
/// Palette "Sanft & modern": gedecktes Indigo/Lavendel + soft Rose.
abstract final class AppColors {
  static const primary = Color(0xFF5B5BD6); // Indigo – Pin, Primäraktionen
  static const primaryDeep = Color(0xFF4340B8); // Verläufe, Tiefe
  static const accent = Color(0xFFE8A0BF); // soft Rose – Akzent
  static const accentSoft = Color(0xFFF6D9E4); // Flächen
  static const ink = Color(0xFF2A2A40); // Text auf hell
  static const surface = Color(0xFFFBFAFF); // Hintergrund hell
}

/// Zentrales App-Theme. Light und Dark aus einem Seed abgeleitet,
/// damit Farben in beiden Modi konsistent bleiben (Material 3).
abstract final class AppTheme {
  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(secondary: AppColors.accent);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.light ? AppColors.surface : null,
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}
