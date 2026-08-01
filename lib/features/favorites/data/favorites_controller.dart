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

  @override
  List<FavoritePlace> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(FavoritePlace.fromJson)
          .whereType<FavoritePlace>()
          .toList();
      state = list;
    } catch (_) {
      // Beschaedigter Eintrag -> ignorieren (Default bleibt leer).
    }
  }

  bool isFavorite(String placeRef) => state.any((f) => f.placeRef == placeRef);

  /// Fuegt hinzu (falls neu) oder entfernt (falls vorhanden). Gibt zurueck, ob
  /// der Platz danach favorisiert ist (fuer die Toast-Meldung).
  Future<bool> toggle(FavoritePlace fav) async {
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
