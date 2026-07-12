import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/changing_place.dart';

/// Fehler beim Abruf der Overpass API.
class OverpassException implements Exception {
  const OverpassException(this.message);
  final String message;
  @override
  String toString() => 'OverpassException: $message';
}

/// Lädt Wickelplätze aus OpenStreetMap über die Overpass API.
///
/// Overpass ist ein read-only Query-Interface auf OSM-Daten. Wir fragen
/// alle Objekte mit `changing_table=yes` innerhalb einer Bounding-Box ab.
/// Kein API-Key nötig; wir setzen ein Timeout und einen aussagekräftigen
/// User-Agent (Overpass-Etikette).
class OverpassRepository {
  OverpassRepository({http.Client? client, this.endpoint = _defaultEndpoint})
      : _client = client ?? http.Client();

  static const _defaultEndpoint = 'https://overpass-api.de/api/interpreter';
  static const _userAgent = 'Wickelfinder/0.1 (+https://github.com/Labushuya/wickelfinder)';

  final http.Client _client;
  final String endpoint;

  /// Baut die Overpass-QL-Query für eine Bounding-Box.
  /// Reihenfolge der Koordinaten in Overpass: (süd, west, nord, ost).
  static String buildQuery({
    required double south,
    required double west,
    required double north,
    required double east,
    int timeoutSeconds = 25,
  }) {
    final bbox = '$south,$west,$north,$east';
    return '''
[out:json][timeout:$timeoutSeconds];
(
  node["changing_table"="yes"]($bbox);
  way["changing_table"="yes"]($bbox);
  relation["changing_table"="yes"]($bbox);
);
out center;
''';
  }

  /// Parst eine Overpass-JSON-Antwort zu einer Liste von [ChangingPlace].
  /// Statisch und pur -> direkt unit-testbar ohne Netzwerk.
  static List<ChangingPlace> parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['elements'] is! List) {
      throw const OverpassException('Unerwartetes Antwortformat');
    }
    final elements = (decoded['elements'] as List).cast<Map<String, dynamic>>();
    return elements
        .map(ChangingPlace.fromOverpassElement)
        .whereType<ChangingPlace>()
        .toList(growable: false);
  }

  /// Ruft Wickelplätze innerhalb der Bounding-Box ab.
  Future<List<ChangingPlace>> fetchInBoundingBox({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final query = buildQuery(
      south: south,
      west: west,
      north: north,
      east: east,
    );

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'User-Agent': _userAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw OverpassException('Netzwerkfehler: $e');
    }

    if (res.statusCode != 200) {
      throw OverpassException('HTTP ${res.statusCode}');
    }
    return parseResponse(res.body);
  }

  void dispose() => _client.close();
}
