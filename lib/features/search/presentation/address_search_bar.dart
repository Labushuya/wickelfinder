import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../data/geocoding_repository.dart';

/// Stellt das [GeocodingRepository] bereit.
final geocodingRepositoryProvider = Provider<GeocodingRepository>((ref) {
  final repo = GeocodingRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Adress-/Ortssuchleiste mit Live-Vorschlaegen (debounced Nominatim).
/// Bei Auswahl eines Treffers wird [onSelected] mit der Zielkoordinate gerufen.
class AddressSearchBar extends ConsumerStatefulWidget {
  const AddressSearchBar({super.key, required this.onSelected, this.trailing});

  final void Function(LatLng target) onSelected;

  /// Optionales Widget rechts in der Suchleiste (z. B. das 3-Punkt-Menue),
  /// solange kein Suchtext eingegeben ist.
  final Widget? trailing;

  @override
  ConsumerState<AddressSearchBar> createState() => _AddressSearchBarState();
}

class _AddressSearchBarState extends ConsumerState<AddressSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GeoResult> _suggestions = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() => _loading = true);
    try {
      final results = await ref.read(geocodingRepositoryProvider).search(value);
      if (mounted) setState(() => _suggestions = results);
    } catch (_) {
      if (mounted) setState(() => _suggestions = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(GeoResult r) {
    _controller.text = r.label;
    setState(() => _suggestions = const []);
    FocusScope.of(context).unfocus();
    widget.onSelected(r.location);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(28),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Adresse oder Ort suchen …',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _suggestions = const []);
                            },
                          )
                        : widget.trailing),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (_, i) {
                final r = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 20),
                  title: Text(
                    r.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _select(r),
                );
              },
            ),
          ),
      ],
    );
  }
}
