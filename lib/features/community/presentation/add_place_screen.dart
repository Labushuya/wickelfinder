import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../data/community_repository.dart';
import 'community_providers.dart';

/// Screen zum Hinzufuegen eines neuen Wickelplatzes.
/// Der Nutzer verschiebt die Karte, bis das zentrale Fadenkreuz auf dem Ort
/// liegt, und ergaenzt optionale Angaben.
class AddPlaceScreen extends ConsumerStatefulWidget {
  const AddPlaceScreen({super.key, required this.initialCenter});

  final LatLng initialCenter;

  @override
  ConsumerState<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends ConsumerState<AddPlaceScreen> {
  final _mapController = MapController();
  final _nameController = TextEditingController();
  final _hintController = TextEditingController();
  bool? _wheelchair;
  bool? _fee;
  bool _saving = false;

  late LatLng _center = widget.initialCenter;

  @override
  void dispose() {
    _nameController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wickelplatz hinzufügen')),
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
                    initialCenter: widget.initialCenter,
                    initialZoom: 16,
                    onPositionChanged: (pos, _) => _center = pos.center,
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
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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
    try {
      await repo.addPlace(
        lat: _center.latitude,
        lon: _center.longitude,
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        locationHint: _hintController.text.trim().isEmpty
            ? null
            : _hintController.text.trim(),
        wheelchair: _wheelchair,
        fee: _fee,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Platz hinzugefügt. Danke!')),
      );
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
