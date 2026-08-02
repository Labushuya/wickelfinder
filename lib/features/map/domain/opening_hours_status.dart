/// Best-Effort-Berechnung des „jetzt geöffnet"-Status aus einem rohen OSM-
/// `opening_hours`-String. Dreiwertig und bewusst konservativ: nur wenn das
/// Muster SICHER erkannt wird, gibt es open/closed — sonst [OpenState.unknown]
/// (nie fälschlich „geschlossen" oder „offen").
///
/// Deckt dieselbe Grammatik-Teilmenge ab wie der Formatter (siehe
/// opening_hours_format.dart): eine Tages-/Zeitregel, optional eine einfache
/// Schliess-Klausel. `PH`/`SH` (Feiertage/Ferien) → unknown (kein Kalender).
/// Mehrregel-`;`, Saison/Monate, Kommentare, Über-Nacht-Intervalle → unknown.
///
/// Kein internes `DateTime.now()` — die Zeit ist Parameter (deterministisch,
/// testbar).
library;

enum OpenState { open, closed, unknown }

/// OSM-Wochentagskürzel → Dart `DateTime.weekday` (Mo=1 … So=7).
const Map<String, int> _dayNum = {
  'Mo': 1,
  'Tu': 2,
  'We': 3,
  'Th': 4,
  'Fr': 5,
  'Sa': 6,
  'Su': 7,
};

OpenState openStateAt(String raw, DateTime now) {
  final s = raw.trim();
  if (s.isEmpty) return OpenState.unknown;

  if (s == '24/7') return OpenState.open;

  // Optional eine einfache Schliess-Klausel am Ende abtrennen.
  String head = s;
  String? offTail;
  final semi = s.lastIndexOf(';');
  if (semi > 0) {
    head = s.substring(0, semi).trim();
    offTail = s.substring(semi + 1).trim();
  } else if (s.contains(';')) {
    // Fuehrendes ';' o.ae. -> nicht sicher parsbar.
    return OpenState.unknown;
  }

  final weekday = now.weekday; // 1..7

  // Schliess-Klausel auswerten (nur wenn vorhanden).
  if (offTail != null) {
    final offDays = _parseOffClause(offTail);
    if (offDays == null) return OpenState.unknown; // enthaelt PH/SH/Unklares
    if (offDays.contains(weekday)) return OpenState.closed;
  }

  // Hauptregel: (optional Tage) + genau EIN Zeitfenster.
  return _evalSingleRule(head, now, weekday);
}

/// Wertet EINE Regel „[Tage ]HH:MM-HH:MM" gegen die aktuelle Zeit aus.
OpenState _evalSingleRule(String rule, DateTime now, int weekday) {
  // Reines Zeitfenster ohne Tagesangabe -> gilt taeglich.
  final timeOnly = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$');
  final tm = timeOnly.firstMatch(rule);
  if (tm != null) {
    return _inWindow(now, tm, 1, 2, 3, 4);
  }

  // Tagesangabe + ein Zeitfenster.
  final full = RegExp(
    r'^([A-Za-z,\-]+)\s+(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$',
  );
  final m = full.firstMatch(rule);
  if (m == null) return OpenState.unknown;

  final days = _parseDays(m.group(1)!);
  if (days == null) return OpenState.unknown;
  if (!days.contains(weekday)) return OpenState.closed; // heute nicht geoeffnet
  return _inWindow(now, m, 2, 3, 4, 5);
}

/// Prueft, ob `now` im Zeitfenster [start,end) liegt. Ueber-Nacht-Intervalle
/// (Ende <= Start) werden NICHT unterstuetzt -> unknown (lieber ehrlich).
OpenState _inWindow(
  DateTime now,
  RegExpMatch m,
  int sh,
  int sm,
  int eh,
  int em,
) {
  final startH = int.parse(m.group(sh)!);
  final startM = int.parse(m.group(sm)!);
  final endH = int.parse(m.group(eh)!);
  final endM = int.parse(m.group(em)!);
  final start = startH * 60 + startM;
  final end = endH * 60 + endM;
  if (end <= start) return OpenState.unknown; // Ueber-Nacht -> nicht sicher
  final cur = now.hour * 60 + now.minute;
  return (cur >= start && cur < end) ? OpenState.open : OpenState.closed;
}

/// Parst einen Tages-Ausdruck ("Mo-Fr", "Mo,We,Fr", "Sa") zu einer Menge von
/// weekday-Nummern. null bei unbekanntem Kuerzel.
Set<int>? _parseDays(String expr) {
  if (expr.contains('-')) {
    final parts = expr.split('-');
    if (parts.length != 2) return null;
    final a = _dayNum[parts[0]];
    final b = _dayNum[parts[1]];
    if (a == null || b == null) return null;
    final out = <int>{};
    // Bereich, ggf. ueber Sonntag hinaus (z.B. Sa-Mo).
    var d = a;
    while (true) {
      out.add(d);
      if (d == b) break;
      d = d == 7 ? 1 : d + 1;
    }
    return out;
  }
  final out = <int>{};
  for (final t in expr.split(',')) {
    final n = _dayNum[t];
    if (n == null) return null;
    out.add(n);
  }
  return out;
}

/// Parst eine Schliess-Klausel "Su,PH off" / "Su off" zu den geschlossenen
/// weekday-Nummern. `PH`/`SH` (Feiertage/Ferien) werden UEBERSPRUNGEN — wir
/// kennen keinen Kalender, aber der Werktags-Status bleibt dadurch auswertbar
/// (z.B. "Mo-Fr 08:00-18:00; PH off" ist Mo–Fr klar offen). Gibt null zurueck,
/// wenn die Klausel selbst nicht sauber parsbar ist (-> Aufrufer: unknown).
Set<int>? _parseOffClause(String tail) {
  final m = RegExp(r'^([A-Za-z,]+)\s+off$').firstMatch(tail);
  if (m == null) return null;
  final tokens = m.group(1)!.split(',');
  final out = <int>{};
  for (final t in tokens) {
    if (t == 'PH' || t == 'SH') continue; // kein Kalender -> ignorieren
    final n = _dayNum[t];
    if (n == null) return null;
    out.add(n);
  }
  return out;
}
