import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/bottom_toast.dart';
import '../data/community_repository.dart';
import 'community_providers.dart';

/// Admin-Screen zur Foto-Freigabe: listet wartende Fotos mit Vorschau und
/// erlaubt Freigeben/Ablehnen. Serverseitig durch is_admin abgesichert
/// (admin_pending_photos / admin_review_photo werfen sonst admin_required).
class PhotoReviewScreen extends ConsumerWidget {
  const PhotoReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPendingPhotosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos prüfen [Admin]')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Konnte nicht geladen werden.')),
        data: (photos) {
          if (photos.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Keine Fotos warten auf Freigabe.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminPendingPhotosProvider),
            child: ListView.separated(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              itemCount: photos.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = photos[i];
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: p.signedUrl,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: 200,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 200,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.placeRef,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.check),
                              label: const Text('Freigeben'),
                              onPressed: () =>
                                  _review(context, ref, p.photoId, true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text('Ablehnen'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              onPressed: () =>
                                  _review(context, ref, p.photoId, false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    String photoId,
    bool approve,
  ) async {
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.adminReviewPhoto(photoId, approve: approve);
      ref.invalidate(adminPendingPhotosProvider);
      ref.invalidate(adminModerationCountsProvider);
      if (context.mounted) {
        showBottomToast(
          context,
          approve ? 'Foto freigegeben.' : 'Foto abgelehnt.',
        );
      }
    } on CommunityException catch (e) {
      if (context.mounted) showBottomToast(context, e.userMessage);
    } catch (_) {
      if (context.mounted) showBottomToast(context, 'Aktion fehlgeschlagen.');
    }
  }
}
