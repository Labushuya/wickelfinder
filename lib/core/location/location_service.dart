import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Kapselt Standortabfrage inkl. Permission-Handling (geolocator).
/// Der Standort wird nur on-device verwendet (DSGVO), nie an einen Server
/// von Wickelfinder gesendet.
abstract final class LocationService {
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
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // Kein Dienst / keine Plugin-Anbindung (z. B. Test) / abgelehnt.
      return null;
    }
  }
}
