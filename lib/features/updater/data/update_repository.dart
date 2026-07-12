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
    final apk = assets.cast<Map>().firstWhere(
      (a) => (a['name'] as String? ?? '').endsWith('.apk'),
      orElse: () => const {},
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
  /// Vergleicht MAJOR.MINOR.PATCH numerisch.
  static bool isNewer(String candidate, String current) {
    final c = _parts(candidate);
    final o = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] != o[i]) return c[i] > o[i];
    }
    return false;
  }

  static List<int> _parts(String v) {
    final nums = v.split('+').first.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < nums.length ? (int.tryParse(nums[i]) ?? 0) : 0,
    ];
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
