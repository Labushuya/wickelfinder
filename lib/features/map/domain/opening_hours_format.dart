/// Best-Effort-Formatter fuer den rohen OSM-`opening_hours`-String.
///
/// Ziel (bewusst begrenzt): NUR gaengige, eindeutige Muster in lesbares Deutsch
/// uebersetzen. Alles, was auch nur ansatzweise komplexer ist (mehrere Regeln,
/// Feiertage `PH`, `off`, Monate/Saison, Kommentare in Anfuehrungszeichen,
/// Unbekanntes), wird **unveraendert** zurueckgegeben — lieber ehrlich der rohe
/// OSM-Text als eine falsche Uebersetzung.
///
/// KEIN vollstaendiger opening_hours-Parser (die Grammatik mit Ferien/Saison/
/// Ausnahmen ist beruechtigt wartungsintensiv und widerspricht dem Low-
/// Maintenance-Ziel der App).
library;

/// Deutsche Wochentags-Kuerzel, indexiert nach OSM-Kuerzel.
const Map<String, String> _dayDe = {
  'Mo': 'Mo',
  'Tu': 'Di',
  'We': 'Mi',
  'Th': 'Do',
  'Fr': 'Fr',
  'Sa': 'Sa',
  'Su': 'So',
};

/// Uebersetzt gaengige OSM-`opening_hours`-Muster nach Deutsch; faellt bei allem
/// Nicht-eindeutigen auf den (getrimmten) Rohtext zurueck.
String formatOpeningHours(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;

  // 24/7 — durchgehend.
  if (s == '24/7') return 'Durchgehend geöffnet (24/7)';

  // Nur ein einzelnes Zeitfenster ohne Tagesangabe, z. B. "08:00-18:00".
  final timeOnly = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$');
  final tm = timeOnly.firstMatch(s);
  if (tm != null) {
    return 'Täglich ${_time(tm, 1, 2)}–${_time(tm, 3, 4)} Uhr';
  }

  // Tagesangabe + genau EIN Zeitfenster, z. B.:
  //   "Mo-Fr 08:00-18:00"  |  "Mo,We,Fr 09:00-17:00"  |  "Sa 10:00-14:00"
  // Bewusst nur EINE Regel (kein ';' / kein zweites Fenster / kein PH/off).
  final full = RegExp(
    r'^([A-Za-z,\-]+)\s+(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$',
  );
  final m = full.firstMatch(s);
  if (m != null) {
    final days = _formatDays(m.group(1)!);
    if (days != null) {
      return '$days ${_time(m, 2, 3)}–${_time(m, 4, 5)} Uhr';
    }
  }

  // Alles andere: ehrlich der rohe Text.
  return s;
}

/// "08:00" -> "8", "08:30" -> "8:30". Minuten nur zeigen, wenn != 00.
String _time(RegExpMatch m, int hGroup, int minGroup) {
  final h = int.parse(m.group(hGroup)!);
  final min = m.group(minGroup)!;
  return min == '00' ? '$h' : '$h:$min';
}

/// Uebersetzt einen Tages-Ausdruck ("Mo-Fr", "Mo,We,Fr", "Sa") nach Deutsch.
/// Gibt null zurueck, wenn ein Kuerzel unbekannt ist (dann Fallback auf Rohtext).
String? _formatDays(String expr) {
  // Bereich "Mo-Fr".
  if (expr.contains('-')) {
    final parts = expr.split('-');
    if (parts.length != 2) return null;
    final a = _dayDe[parts[0]];
    final b = _dayDe[parts[1]];
    if (a == null || b == null) return null;
    return '$a–$b';
  }
  // Liste "Mo,We,Fr" oder einzelner Tag "Sa".
  final days = expr.split(',');
  final out = <String>[];
  for (final d in days) {
    final de = _dayDe[d];
    if (de == null) return null;
    out.add(de);
  }
  return out.join(', ');
}
