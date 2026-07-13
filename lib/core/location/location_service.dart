import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kapselt Standortabfrage inkl. Permission-Handling (geolocator).
/// Der Standort wird nur on-device verwendet (DSGVO), nie an einen Server
/// von Wickelfinder gesendet. Der letzte bekannte Standort wird lokal
/// gespeichert, damit die Karte beim Start sofort dort startet (kein
/// Berlin-Aufblitzen).
abstract final class LocationService {
  static const _keyLat = 'last_lat';
  static const _keyLon = 'last_lon';

  /// Zuletzt gespeicherter Standort (aus vorheriger Sitzung), sofort verfuegbar.
  static Future<LatLng?> lastKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_keyLat);
      final lon = prefs.getDouble(_keyLon);
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persist(LatLng pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLat, pos.latitude);
      await prefs.setDouble(_keyLon, pos.longitude);
    } catch (_) {
      // nicht fatal
    }
  }

  /// Holt die aktuelle Position, sofern der Dienst aktiviert und die
  /// Berechtigung erteilt ist. Gibt null zurueck, wenn nicht verfuegbar oder
  /// abgelehnt — der Aufrufer bleibt dann bei der bisherigen Kartenposition.
  static Future<LatLng?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      await _persist(latLng); // fuer schnellen Start beim naechsten Mal
      return latLng;
    } catch (_) {
      // Kein Dienst / keine Plugin-Anbindung (z. B. Test) / abgelehnt.
      return null;
    }
  }
}
