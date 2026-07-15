import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../map/domain/changing_place.dart';
import '../data/community_repository.dart';
import 'community_providers.dart';

/// Screen zum Hinzufuegen ODER Bearbeiten eines Wickelplatzes.
/// Der Nutzer verschiebt die Karte, bis das zentrale Fadenkreuz auf dem Ort
/// liegt, und ergaenzt optionale Angaben. Ist [editPlace] gesetzt, werden die
/// Felder vorbefuellt und beim Speichern der Platz aktualisiert.
class AddPlaceScreen extends ConsumerStatefulWidget {
  const AddPlaceScreen({
    super.key,
    required this.initialCenter,
    this.editPlace,
  });

  final LatLng initialCenter;

  /// Wenn gesetzt: Bearbeiten-Modus fuer diesen eigenen Platz.
  final ChangingPlace? editPlace;

  bool get isEdit => editPlace != null;

  @override
  ConsumerState<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends ConsumerState<AddPlaceScreen> {
  final _mapController = MapController();
  late final _nameController = TextEditingController(
    text: widget.editPlace?.name ?? '',
  );
  late final _hintController = TextEditingController(
    text: widget.editPlace?.locationHint ?? '',
  );
  late bool? _wheelchair = widget.editPlace?.wheelchairAccessible;
  late bool? _fee = widget.editPlace?.fee;
  bool _saving = false;

  late LatLng _center = widget.editPlace?.location ?? widget.initialCenter;

  @override
  void dispose() {
    _nameController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEdit ? 'Wickelplatz bearbeiten' : 'Wickelplatz hinzufügen',
        ),
      ),
      body: Column(
        children: [
          // Karte mit fixiertem Fadenkreuz in der Mitte.
          SizedBox(
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 16,
                    onPositionChanged: (pos, _) =>
                        _center = pos.center ?? _center,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'de.wickelfinder.app',
                    ),
                  ],
                ),
                const IgnorePointer(
                  child: Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 44,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Ort per Verschieben der Karte einstellen.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'z. B. Einkaufszentrum, Café …',
                  ),
                ),
                TextField(
                  controller: _hintController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Hinweis zur Lage (optional)',
                    hintText: 'z. B. im 1. OG bei den Toiletten',
                  ),
                ),
                const SizedBox(height: 8),
                _TriStateRow(
                  label: 'Barrierefrei',
                  value: _wheelchair,
                  onChanged: (v) => setState(() => _wheelchair = v),
                ),
                _TriStateRow(
                  label: 'Kostenlos',
                  value: _fee == null ? null : !_fee!,
                  onChanged: (v) =>
                      setState(() => _fee = v == null ? null : !v),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bitte keine persönlichen Daten Dritter eingeben.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Platz speichern'),
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    String? emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

    try {
      final edit = widget.editPlace;
      if (edit != null) {
        await repo.updatePlace(
          id: edit.id,
          lat: _center.latitude,
          lon: _center.longitude,
          name: emptyToNull(_nameController.text),
          locationHint: emptyToNull(_hintController.text),
          wheelchair: _wheelchair,
          fee: _fee,
        );
        // Refresh HIER ausloesen, wo der ConsumerState-ref garantiert lebt.
        // (Frueher lief der Refresh ueber den bereits gepoppten Sheet-Ref und
        // wurde nie ausgefuehrt -> Edits erschienen nicht.)
        await refreshCommunityDataFromWidget(ref);
        messenger.showSnackBar(
          const SnackBar(content: Text('Platz aktualisiert.')),
        );
      } else {
        await repo.addPlace(
          lat: _center.latitude,
          lon: _center.longitude,
          name: emptyToNull(_nameController.text),
          locationHint: emptyToNull(_hintController.text),
          wheelchair: _wheelchair,
          fee: _fee,
        );
        await refreshCommunityDataFromWidget(ref);
        messenger.showSnackBar(
          const SnackBar(content: Text('Platz hinzugefügt. Danke!')),
        );
      }
      navigator.pop(true);
    } on CommunityException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
      setState(() => _saving = false);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Speichern fehlgeschlagen.')),
      );
      setState(() => _saving = false);
    }
  }
}

/// Ja/Nein/Unbekannt-Auswahl als SegmentedButton.
class _TriStateRow extends StatelessWidget {
  const _TriStateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'yes', label: Text('Ja')),
              ButtonSegment(value: 'unknown', label: Text('?')),
              ButtonSegment(value: 'no', label: Text('Nein')),
            ],
            selected: {
              value == null
                  ? 'unknown'
                  : value!
                  ? 'yes'
                  : 'no',
            },
            onSelectionChanged: (sel) => onChanged(switch (sel.first) {
              'yes' => true,
              'no' => false,
              _ => null,
            }),
          ),
        ],
      ),
    );
  }
}
