import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Ein Suchtreffer der Adresssuche.
class GeoResult {
  const GeoResult({required this.label, required this.location});

  /// Anzeigename (z. B. "Alexanderplatz, Mitte, Berlin").
  final String label;
  final LatLng location;
}

/// Adress-/Ortssuche via Nominatim (OpenStreetMap-Geocoder).
/// Kostenlos, kein API-Key. Nominatim verlangt einen aussagekraeftigen
/// User-Agent und moderate Request-Raten (Debounce im UI).
class GeocodingRepository {
  GeocodingRepository({http.Client? client})
    : _client = client ?? http.Client();

  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent =
      'Wickelfinder/0.5 (+https://github.com/Labushuya/wickelfinder)';

  final http.Client _client;

  /// Sucht nach [query] und liefert bis zu [limit] Treffer.
  /// Leere/zu kurze Query -> leere Liste (spart Nominatim-Last).
  Future<List<GeoResult>> search(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'q': q,
        'format': 'jsonv2',
        'limit': '$limit',
        'addressdetails': '0',
        // Fokus auf DE, aber nicht hart begrenzt (fuzzy bleibt moeglich).
        'accept-language': 'de',
      },
    );

    final res = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) return const [];
    return parseResults(res.body);
  }

  /// Parst eine Nominatim-jsonv2-Antwort. Statisch/pur -> unit-testbar.
  static List<GeoResult> parseResults(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final results = <GeoResult>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      final name = item['display_name'] as String?;
      if (lat == null || lon == null || name == null) continue;
      results.add(GeoResult(label: name, location: LatLng(lat, lon)));
    }
    return results;
  }

  void dispose() => _client.close();
}
