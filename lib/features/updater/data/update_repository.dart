import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Ein verfuegbares Update aus den GitHub Releases.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
  });

  final String version; // ohne fuehrendes 'v'
  final String notes;
  final String apkUrl;
  final String apkName;
}

/// Prueft GitHub Releases auf eine neuere App-Version und laedt die APK.
/// Nutzt die oeffentliche GitHub-API (kein Token noetig fuer public repos).
class UpdateRepository {
  UpdateRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _latestUrl =
      'https://api.github.com/repos/Labushuya/wickelfinder/releases/latest';

  final http.Client _client;

  /// Gibt ein [AppUpdate] zurueck, wenn eine neuere Version verfuegbar ist,
  /// sonst null. Fehler (offline etc.) werden als null behandelt.
  Future<AppUpdate?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // z. B. "0.6.0"

      final res = await _client.get(
        Uri.parse(_latestUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode != 200) return null;

      final update = parseRelease(res.body);
      if (update == null) return null;
      if (!isNewer(update.version, current)) return null;
      return update;
    } catch (_) {
      return null;
    }
  }

  /// Parst die GitHub-Releases-Antwort. Statisch/pur -> unit-testbar.
  static AppUpdate? parseRelease(String body) {
    final json = _tryDecode(body);
    if (json == null) return null;
    final tag = (json['tag_name'] as String?)?.replaceFirst('v', '');
    if (tag == null) return null;
    final assets = (json['assets'] as List?) ?? const [];
    final apk = assets.cast<Map<String, dynamic>>().firstWhere(
      (a) => (a['name'] as String? ?? '').endsWith('.apk'),
      orElse: () => const <String, dynamic>{},
    );
    final url = apk['browser_download_url'] as String?;
    final name = apk['name'] as String?;
    if (url == null || name == null) return null;
    return AppUpdate(
      version: tag,
      notes: (json['body'] as String?) ?? '',
      apkUrl: url,
      apkName: name,
    );
  }

  /// SemVer-Vergleich: ist [candidate] echt neuer als [current]?
  ///
  /// Ordnet nach SemVer-Precedence:
  /// 1. MAJOR.MINOR.PATCH numerisch.
  /// 2. Eine Version MIT Prerelease (-beta.N) ist NIEDRIGER als dieselbe
  ///    Version OHNE Prerelease (1.0.0-beta < 1.0.0).
  /// 3. Prerelease-Identifier dot-getrennt: numerisch < alphanumerisch,
  ///    numerische numerisch (beta.2 < beta.10), sonst lexikografisch.
  /// 4. Build-Metadaten (+30) werden ignoriert.
  /// Wirft nie; unparsebare Segmente werden zu 0/leer.
  static bool isNewer(String candidate, String current) =>
      compare(candidate, current) > 0;

  /// Liefert <0 wenn [a] aelter, 0 wenn gleich, >0 wenn [a] neuer als [b].
  static int compare(String a, String b) {
    final ka = _sortKey(a);
    final kb = _sortKey(b);
    final len = ka.length > kb.length ? ka.length : kb.length;
    for (var i = 0; i < len; i++) {
      // Fehlende Elemente zaehlen als "kleiner": kuerzere Prerelease-Kette
      // hat niedrigere Precedence (1.0.0-beta < 1.0.0-beta.1).
      final va = i < ka.length ? ka[i] : const _Ident.empty();
      final vb = i < kb.length ? kb[i] : const _Ident.empty();
      final cmp = va.compareTo(vb);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  /// Baut einen vergleichbaren Sortier-Key: erst drei numerische Elemente
  /// (major, minor, patch), dann ein Prerelease-Flag (Stable=1 > Prerelease=0),
  /// dann pro Prerelease-Identifier ein [_Ident].
  static List<_Ident> _sortKey(String version) {
    // Build-Metadaten und fuehrendes 'v' entfernen.
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    v = v.split('+').first;

    final dashIdx = v.indexOf('-');
    final core = dashIdx >= 0 ? v.substring(0, dashIdx) : v;
    final pre = dashIdx >= 0 ? v.substring(dashIdx + 1) : '';

    final nums = core.split('.');
    final key = <_Ident>[
      for (var i = 0; i < 3; i++)
        _Ident.number(
          i < nums.length ? (int.tryParse(nums[i].trim()) ?? 0) : 0,
        ),
    ];

    // Stable rankt hoeher als jede Prerelease derselben Kernversion.
    key.add(_Ident.number(pre.isEmpty ? 1 : 0));

    if (pre.isNotEmpty) {
      for (final id in pre.split('.')) {
        final n = int.tryParse(id.trim());
        key.add(n != null ? _Ident.number(n) : _Ident.text(id.trim()));
      }
    }
    return key;
  }

  /// Laedt die APK in den temporaeren Ordner und gibt den Pfad zurueck.
  /// [onProgress] meldet 0.0..1.0 (falls Content-Length bekannt).
  Future<String> downloadApk(
    AppUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final req = http.Request('GET', Uri.parse(update.apkUrl));
    final resp = await _client.send(req);
    final total = resp.contentLength ?? 0;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${update.apkName}');
    final sink = file.openWrite();
    var received = 0;

    await for (final chunk in resp.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
    return file.path;
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}

/// Ein Precedence-Element eines Sortier-Keys. Numerische Identifier vergleichen
/// numerisch, alphanumerische lexikografisch; numerisch < alphanumerisch
/// (SemVer 9.4). Ein leeres Element (fehlende Kette) ist kleiner als jedes
/// vorhandene Element.
class _Ident implements Comparable<_Ident> {
  const _Ident.number(int value) : _kind = 1, _num = value, _str = '';
  const _Ident.text(String value) : _kind = 2, _num = 0, _str = value;
  const _Ident.empty() : _kind = 0, _num = 0, _str = '';

  final int _kind; // 0 = leer, 1 = numerisch, 2 = alphanumerisch
  final int _num;
  final String _str;

  @override
  int compareTo(_Ident other) {
    if (_kind != other._kind) return _kind.compareTo(other._kind);
    switch (_kind) {
      case 1:
        return _num.compareTo(other._num);
      case 2:
        return _str.compareTo(other._str);
      default:
        return 0;
    }
  }
}
