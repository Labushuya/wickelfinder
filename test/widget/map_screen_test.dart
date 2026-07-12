import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/community/domain/place_stats.dart';
import 'package:wickelfinder/features/community/presentation/community_providers.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';
import 'package:wickelfinder/features/map/presentation/map_screen.dart';
import 'package:wickelfinder/features/map/presentation/place_detail_sheet.dart';

/// Haengt einen PlaceDetailSheet in einen ProviderScope, in dem stats leer sind
/// (kein echtes Backend im Test).
Widget _sheet(ChangingPlace place) => ProviderScope(
  overrides: [
    statsProvider.overrideWith(
      (ref, placeRef) async => PlaceStats.empty(placeRef),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(body: PlaceDetailSheet(place: place)),
  ),
);

void main() {
  testWidgets('MapScreen zeigt die Adress-Suchleiste', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mergedPlacesProvider.overrideWith((ref, bbox) async => const []),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Adresse oder Ort suchen …'), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('PlaceDetailSheet zeigt Name und Infozeilen', (tester) async {
    const place = ChangingPlace(
      id: 'node/1',
      location: LatLng(52.5, 13.4),
      name: 'Café Klein',
      wheelchairAccessible: true,
      fee: false,
      locationHint: 'Im Erdgeschoss',
    );

    await tester.pumpWidget(_sheet(place));
    await tester.pump();

    expect(find.text('Café Klein'), findsOneWidget);
    expect(find.text('Im Erdgeschoss'), findsOneWidget);
    expect(find.text('Barrierefrei zugänglich'), findsOneWidget);
    expect(find.text('Kostenlos'), findsOneWidget);
    expect(find.text('Quelle: OpenStreetMap'), findsOneWidget);
    // Ohne konfiguriertes Backend erscheint kein Bewerten-Button.
    expect(find.text('Noch keine Bewertungen'), findsOneWidget);
  });

  testWidgets('PlaceDetailSheet nutzt Fallback-Titel ohne Namen', (
    tester,
  ) async {
    const place = ChangingPlace(id: 'node/2', location: LatLng(1, 2));

    await tester.pumpWidget(_sheet(place));
    await tester.pump();

    expect(find.text('Wickelplatz'), findsOneWidget);
  });
}
