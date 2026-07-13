import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verwaltet den Theme-Modus (hell/dunkel/system) und persistiert ihn.
///
/// Default ist HELL (Marken-Look), auch wenn das System dunkel ist — der
/// Nutzer entscheidet beim ersten Start (Dialog) bzw. in den Einstellungen,
/// ob die App dem System folgen soll.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  SharedPreferences? _prefs;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.light; // Default bis geladen: helle Marke.
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs?.getString(_key);
    if (stored != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.light,
      );
    }
  }

  /// True, wenn der Nutzer bereits eine bewusste Wahl getroffen hat.
  bool get hasChosen => _prefs?.getString(_key) != null;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, mode.name);
  }

  /// Schnell-Toggle hell <-> dunkel (ignoriert 'system').
  Future<void> toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
