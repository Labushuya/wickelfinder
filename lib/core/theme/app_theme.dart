import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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
  // Dark-Mode: Anthrazit + aufgehellte Marken-Akzente fuer Kontrast.
  static const darkSurface = Color(0xFF1C1C24); // Anthrazit
  static const darkPrimary = Color(0xFF9B9BF0); // aufgehelltes Indigo
}

/// Zentrales App-Theme. Light und Dark aus einem Seed abgeleitet,
/// damit Farben in beiden Modi konsistent bleiben (Material 3).
abstract final class AppTheme {
  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    var scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    // Akzent-Container nur im Light-Mode mit soft-Rose ueberschreiben;
    // im Dark-Mode die vom Seed abgeleiteten (dunklen) Container behalten,
    // damit Text darauf lesbar bleibt.
    scheme = isLight
        ? scheme.copyWith(
            secondary: AppColors.accent,
            secondaryContainer: AppColors.accentSoft,
            onSecondaryContainer: AppColors.ink,
            tertiaryContainer: AppColors.accentSoft,
            onTertiaryContainer: AppColors.ink,
          )
        : scheme.copyWith(secondary: AppColors.accent);

    final surfaceColor = isLight ? AppColors.surface : AppColors.darkSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Global etwas kleinere Typo (weiterhin gut lesbar), damit Text nicht den
      // ganzen Raum einnimmt. Ein Eingriff -> wirkt ueber alle textTheme.*.
      textTheme:
          (isLight
                  ? Typography.material2021(
                      platform: defaultTargetPlatform,
                    ).black
                  : Typography.material2021(
                      platform: defaultTargetPlatform,
                    ).white)
              .apply(fontSizeFactor: 0.93),
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
        textStyle: TextStyle(color: scheme.onSurface),
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
        selectedColor: isLight ? AppColors.accentSoft : AppColors.primaryDeep,
        checkmarkColor: isLight ? AppColors.primaryDeep : Colors.white,
        // Kein Checkmark -> Chip-Breite bleibt beim Selektieren konstant,
        // kein Umbruch-Sprung im Wrap. Kompaktes Padding + kleineres Label.
        showCheckmark: false,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        secondarySelectedColor: isLight
            ? AppColors.accentSoft
            : AppColors.primaryDeep,
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
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
      // Info-/Statusmeldungen markant in Markenoptik statt Default-Grau
      // Info-/Statusmeldungen markant in Markenoptik statt Default-Grau
      // (Material-Default waere inverseSurface = dunkles Grau).
      // behavior: fixed -> SnackBar klebt am UNTEREN Rand ueber die volle
      // Breite, UNTERHALB der FABs (Standort/Platz melden), statt als floating
      // ueber ihnen zu erscheinen.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: isLight ? AppColors.primary : AppColors.darkPrimary,
        contentTextStyle: TextStyle(
          color: isLight ? Colors.white : AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: isLight ? AppColors.accentSoft : AppColors.ink,
        elevation: 4,
      ),
    );
  }
}
