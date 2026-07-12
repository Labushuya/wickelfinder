import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wickelfinder/features/map/domain/changing_place.dart';
import 'package:wickelfinder/features/map/presentation/map_providers.dart';
import 'package:wickelfinder/features/map/presentation/map_screen.dart';
import 'package:wickelfinder/features/map/presentation/place_detail_sheet.dart';

void main() {
  testWidgets('MapScreen rendert AppBar-Titel "Wickelfinder"', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [placesProvider.overrideWith((ref, bbox) async => const [])],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Wickelfinder'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
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

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlaceDetailSheet(place: place)),
      ),
    );

    expect(find.text('Café Klein'), findsOneWidget);
    expect(find.text('Im Erdgeschoss'), findsOneWidget);
    expect(find.text('Barrierefrei zugänglich'), findsOneWidget);
    expect(find.text('Kostenlos'), findsOneWidget);
    expect(find.text('Quelle: OpenStreetMap'), findsOneWidget);
  });

  testWidgets('PlaceDetailSheet nutzt Fallback-Titel ohne Namen', (
    tester,
  ) async {
    const place = ChangingPlace(id: 'node/2', location: LatLng(1, 2));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlaceDetailSheet(place: place)),
      ),
    );

    expect(find.text('Wickelplatz'), findsOneWidget);
  });
}
