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
    final isLight = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          secondary: AppColors.accent,
          secondaryContainer: AppColors.accentSoft,
        );

    final surfaceColor = isLight ? AppColors.surface : scheme.surface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceColor,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // Suchleiste / Eingabefelder in Markenoptik.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: TextStyle(color: scheme.outline),
        prefixIconColor: AppColors.primary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      // Aufklapp-Menue in Markenfarben, abgerundet.
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(color: AppColors.ink),
      ),
      // Bottom-Sheets (Detail, Bewerten) abgerundet, Markenflaeche.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        selectedColor: AppColors.accentSoft,
        checkmarkColor: AppColors.primaryDeep,
        backgroundColor: isLight
            ? Colors.white
            : scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
