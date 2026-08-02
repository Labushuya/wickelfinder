import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/favorite_place.dart';

/// Lokaler Favoriten-Speicher (nur auf dem Geraet, kein Login, kein Server).
/// Muster wie ThemeModeController: async laden in build(), optimistisch
/// schreiben. Reihenfolge: neueste zuerst.
///
/// Die API (isFavorite/toggle/Liste) ist bewusst schlank gehalten, damit ein
/// spaeterer optionaler Server-Sync sie unveraendert hydrieren koennte.
class FavoritesController extends Notifier<List<FavoritePlace>> {
  static const _key = 'favorites';
  SharedPreferences? _prefs;
  late final Future<void> _loaded;

  @override
  List<FavoritePlace> build() {
    _loaded = _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(FavoritePlace.fromJson)
          .whereType<FavoritePlace>()
          .toList();
      state = list;
    } catch (_) {
      // Beschaedigter Eintrag ODER Plattform-/Kanal-Fehler -> leer bleiben.
      // Wichtig: _load darf NIE mit Fehler abschliessen, sonst wuerde ein
      // fruehes `await _loaded` in toggle() rethrowen.
    }
  }

  bool isFavorite(String placeRef) => state.any((f) => f.placeRef == placeRef);

  /// Fuegt hinzu (falls neu) oder entfernt (falls vorhanden). Gibt zurueck, ob
  /// der Platz danach favorisiert ist (fuer die Toast-Meldung).
  ///
  /// Wartet erst den initialen [_load] ab, damit ein sehr fruehes Toggle nicht
  /// vom nachlaufenden Laden ueberschrieben wird (Race).
  Future<bool> toggle(FavoritePlace fav) async {
    await _loaded;
    final exists = isFavorite(fav.placeRef);
    state = exists
        ? state.where((f) => f.placeRef != fav.placeRef).toList()
        : [fav, ...state];
    await _persist();
    return !exists;
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _key,
      jsonEncode([for (final f in state) f.toJson()]),
    );
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesController, List<FavoritePlace>>(
      FavoritesController.new,
    );
