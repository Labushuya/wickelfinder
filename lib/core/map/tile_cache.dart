import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

/// Baut einen persistenten Kachel-Cache fuer flutter_map auf.
///
/// Besuchte Kartenkacheln werden lokal (Datei-Store) gespeichert, sodass
/// zuvor angesehene Gebiete auch offline die echte Karte zeigen. Neue Gebiete
/// bleiben offline leer (dann greift der Offline-Hinweis in der UI).
class TileCache {
  TileCache._(this._store);

  final CacheStore _store;
  static TileCache? _instance;

  /// Einmalig initialisieren (idempotent). Legt den Datei-Store an.
  static Future<TileCache> instance() async {
    if (_instance != null) return _instance!;
    final dir = await getTemporaryDirectory();
    final store = FileCacheStore('${dir.path}/wf_tiles');
    _instance = TileCache._(store);
    return _instance!;
  }

  /// Synchroner Zugriff nach erfolgtem [instance] (in main.dart). Null, falls
  /// noch nicht initialisiert -> dann nutzt der TileLayer seinen Default.
  static TileCache? instanceOrNull() => _instance;

  /// TileProvider mit Cache. In den TileLayer einsetzen.
  /// 30 Tage Cache; offline bleiben gecachte Kacheln nutzbar.
  TileProvider provider() =>
      CachedTileProvider(store: _store, maxStale: const Duration(days: 30));
}
