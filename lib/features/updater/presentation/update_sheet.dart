import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../data/update_repository.dart';

final updateRepositoryProvider = Provider<UpdateRepository>((ref) {
  final repo = UpdateRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Markengestyltes Update-Sheet: zeigt Version + Changelog, laedt die APK und
/// oeffnet den System-Installer. Der finale Installations-Dialog kommt
/// technikbedingt vom Android-System (nicht umgehbar, so gewollt sicher).
class UpdateSheet extends ConsumerStatefulWidget {
  const UpdateSheet({super.key, required this.update});

  final AppUpdate update;

  /// Prueft auf Updates und zeigt bei Bedarf das Sheet.
  /// [manual] = true zeigt auch eine "Du bist aktuell"-Meldung.
  static Future<void> checkAndShow(
    BuildContext context,
    WidgetRef ref, {
    bool manual = false,
  }) async {
    final update = await ref.read(updateRepositoryProvider).checkForUpdate();
    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du hast die neueste Version.')),
        );
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpdateSheet(update: update),
    );
  }

  @override
  ConsumerState<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<UpdateSheet> {
  double? _progress;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Update verfügbar', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Version ${widget.update.version}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.update.notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    widget.update.notes,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(value: _progress),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(_busy ? 'Wird geladen …' : 'Jetzt aktualisieren'),
                onPressed: _busy ? null : _downloadAndInstall,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Der Installationsdialog wird vom Android-System angezeigt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final path = await ref
          .read(updateRepositoryProvider)
          .downloadApk(
            widget.update,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      // Oeffnet den System-Paket-Installer (via FileProvider im open_filex).
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Installer konnte nicht öffnen: ${result.message}'),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Download fehlgeschlagen.')),
        );
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }
}
