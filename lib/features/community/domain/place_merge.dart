import 'package:latlong2/latlong.dart';

import '../../map/domain/changing_place.dart';

/// Radius, innerhalb dessen ein Community-Platz als Duplikat eines OSM-Platzes
/// gilt (und daher nicht separat angezeigt wird).
const double kDedupRadiusMeters = 75;

const _distance = Distance();

/// Fuehrt OSM- und Community-Plaetze zu einer Anzeige-Liste zusammen.
///
/// Regeln (bewusst konservativ, um stilles Verschlucken UND Feedback-Hijack
/// zu vermeiden):
/// - Ein Community-Platz wird NUR dann als Duplikat weggelassen, wenn ein
///   OSM-Platz innerhalb [kDedupRadiusMeters] liegt UND semantisch passt
///   (gleicher/aehnlicher Name, oder mindestens einer ohne Namen).
/// - OSM-Plaetze bleiben immer erhalten (read-only Basis).
/// - Feedback bleibt an der jeweils eigenen place_ref haengen — es wird kein
///   Community-Feedback auf einen OSM-Platz umgehaengt.
List<ChangingPlace> mergePlaces({
  required List<ChangingPlace> osm,
  required List<ChangingPlace> community,
}) {
  final result = <ChangingPlace>[...osm];

  for (final c in community) {
    final isDuplicate = osm.any(
      (o) =>
          _distance(o.location, c.location) <= kDedupRadiusMeters &&
          _semanticMatch(o, c),
    );
    if (!isDuplicate) result.add(c);
  }
  return result;
}

/// Zwei Plaetze gelten als "derselbe reale Ort", wenn mindestens einer keinen
/// Namen hat oder die Namen (normalisiert) uebereinstimmen bzw. einer im
/// anderen enthalten ist.
bool _semanticMatch(ChangingPlace a, ChangingPlace b) {
  final na = a.name;
  final nb = b.name;
  if (na == null || nb == null) return true;
  final x = _normalize(na);
  final y = _normalize(nb);
  if (x.isEmpty || y.isEmpty) return true;
  return x == y || x.contains(y) || y.contains(x);
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]'), '');
