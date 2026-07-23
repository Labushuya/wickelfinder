import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/bottom_toast.dart';
import '../data/community_repository.dart';
import '../domain/open_report.dart';
import 'community_providers.dart';

/// Admin-Screen zur Pruefung offener Meldungen. Je Meldung: Grund + (falls Foto)
/// Vorschau, mit Aktionen „Foto löschen" bzw. „Meldung verwerfen". Serverseitig
/// durch is_admin abgesichert (admin_open_reports / admin_delete_photo /
/// admin_dismiss_report werfen sonst admin_required).
class ReportsReviewScreen extends ConsumerWidget {
  const ReportsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminOpenReportsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meldungen [Admin]')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Konnte nicht geladen werden.')),
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Keine offenen Meldungen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminOpenReportsProvider),
            child: ListView.separated(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _ReportCard(report: reports[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});
  final OpenReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  report.kindLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(report.placeRef, style: theme.textTheme.bodySmall),
          if (report.isPhoto && report.signedUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: report.signedUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (report.isPhoto)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Foto löschen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => _deletePhoto(context, ref),
                  ),
                ),
              if (report.isPhoto) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Meldung verwerfen'),
                  onPressed: () => _dismiss(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deletePhoto(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null || report.photoId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto löschen?'),
        content: const Text(
          'Das gemeldete Foto wird endgültig entfernt und die Meldung '
          'geschlossen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.adminDeletePhoto(
        report.photoId!,
        storagePath: report.storagePath,
      );
      refreshModeration(ref);
      if (context.mounted) showBottomToast(context, 'Foto gelöscht.');
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) showBottomToast(context, 'Löschen fehlgeschlagen.');
    }
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.adminDismissReport(report.reportId);
      refreshModeration(ref);
      if (context.mounted) showBottomToast(context, 'Meldung verworfen.');
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) showBottomToast(context, 'Aktion fehlgeschlagen.');
    }
  }
}
