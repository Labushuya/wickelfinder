import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wickelfinder/features/favorites/data/favorites_controller.dart';
import 'package:wickelfinder/features/favorites/domain/favorite_place.dart';

FavoritePlace _fav(String ref) =>
    FavoritePlace(placeRef: ref, lat: 1, lon: 2, name: ref);

/// Wartet, bis der async _load() im build() durchgelaufen ist. pumpEventQueue
/// leert die Event-Queue über mehrere Runden -> robust auch bei künftigen
/// SharedPreferences-Backends, die mehrere Hops brauchen.
Future<void> _settle() => pumpEventQueue();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('FavoritesController', () {
    test('startet leer ohne gespeicherte Daten', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      await _settle();
      expect(c.read(favoritesProvider), isEmpty);
    });

    test(
      'toggle fügt hinzu (Rückgabe true) und entfernt (Rückgabe false)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = makeContainer();
        final ctrl = c.read(favoritesProvider.notifier);
        await _settle();

        final added = await ctrl.toggle(_fav('node/1'));
        expect(added, isTrue);
        expect(ctrl.isFavorite('node/1'), isTrue);

        final removed = await ctrl.toggle(_fav('node/1'));
        expect(removed, isFalse);
        expect(ctrl.isFavorite('node/1'), isFalse);
        expect(c.read(favoritesProvider), isEmpty);
      },
    );

    test(
      'neuester Favorit steht vorne (Reihenfolge [fav, ...state])',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = makeContainer();
        final ctrl = c.read(favoritesProvider.notifier);
        await _settle();

        await ctrl.toggle(_fav('node/1'));
        await ctrl.toggle(_fav('node/2'));
        final list = c.read(favoritesProvider);
        expect(list.first.placeRef, 'node/2');
        expect(list.length, 2);
      },
    );

    test('lädt gespeicherte Favoriten beim Start', () async {
      final stored = jsonEncode([
        _fav('node/1').toJson(),
        _fav('community/abc').toJson(),
      ]);
      SharedPreferences.setMockInitialValues({'favorites': stored});
      final c = makeContainer();
      c.read(favoritesProvider); // Provider instanziieren -> _load() startet
      await _settle();
      final list = c.read(favoritesProvider);
      expect(list.length, 2);
      expect(
        c.read(favoritesProvider.notifier).isFavorite('community/abc'),
        isTrue,
      );
    });

    test('beschädigter Speicher -> leer, kein Absturz', () async {
      SharedPreferences.setMockInitialValues({'favorites': 'kein-json{'});
      final c = makeContainer();
      c.read(favoritesProvider); // Provider instanziieren -> _load() startet
      await _settle();
      expect(c.read(favoritesProvider), isEmpty);
    });

    test('toggle schreibt in den persistenten Speicher', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final ctrl = c.read(favoritesProvider.notifier);
      await _settle();
      await ctrl.toggle(_fav('node/9'));

      // Direkt im (gemockten) Speicher prüfen, dass persistiert wurde.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('favorites');
      expect(raw, isNotNull);
      expect(raw, contains('node/9'));
    });

    test('liest den persistenten Speicher in eine neue Instanz', () async {
      SharedPreferences.setMockInitialValues({
        'favorites': jsonEncode([_fav('node/9').toJson()]),
      });
      final c = makeContainer();
      c.read(favoritesProvider); // Provider instanziieren -> _load() startet
      await _settle();
      expect(c.read(favoritesProvider.notifier).isFavorite('node/9'), isTrue);
    });

    test('sehr frühes toggle überlebt das nachlaufende _load (kein Race)', () async {
      // Speicher enthält bereits node/1; sofort (vor Load-Abschluss) togglen wir
      // node/2 dazu. toggle() wartet _loaded ab -> node/1 UND node/2 im state.
      SharedPreferences.setMockInitialValues({
        'favorites': jsonEncode([_fav('node/1').toJson()]),
      });
      final c = makeContainer();
      final ctrl = c.read(favoritesProvider.notifier);
      // KEIN _settle() vorher -> toggle läuft, während _load() noch nicht fertig ist.
      await ctrl.toggle(_fav('node/2'));
      expect(ctrl.isFavorite('node/1'), isTrue); // vom Load nicht verloren
      expect(ctrl.isFavorite('node/2'), isTrue); // frisch getoggelt
    });
  });
}
