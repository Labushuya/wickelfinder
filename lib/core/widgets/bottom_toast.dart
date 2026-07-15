import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Zeigt eine kurze Meldung als eigenes Overlay GANZ UNTEN am Bildschirmrand
/// (unterhalb evtl. vorhandener FABs), volle Breite minus Rand, in Markenfarbe.
///
/// Bewusst KEIN SnackBar: eine Scaffold-SnackBar erscheint in Flutter immer
/// relativ zur floatingActionButton-Location (floating -> ueber dem FAB; fixed
/// -> schiebt den FAB hoch). Fuer "Banner unter den FABs, FABs unbewegt" wird
/// daher ein eigenes OverlayEntry verwendet.
void showBottomToast(BuildContext context, String message) {
  // rootOverlay: true -> App-weites Overlay UEBER allem (auch ueber einem
  // modalen BottomSheet), sonst laege der Toast hinter dem Sheet und waere
  // unsichtbar. Das war die Ursache, warum der Toast nicht unten erschien.
  final overlay = Overlay.of(context, rootOverlay: true);
  final theme = Theme.of(context);
  final isLight = theme.brightness == Brightness.light;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 12,
      right: 12,
      // Ganz unten, knapp ueber der System-Navigationsleiste (Insets aus dem
      // Overlay-Kontext, nicht aus dem evtl. Sheet-reduzierten Aufrufer-ctx).
      bottom: MediaQuery.viewPaddingOf(ctx).bottom + 12,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isLight ? AppColors.primary : AppColors.darkPrimary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  // Nach ~3s automatisch ausblenden/entfernen (idempotent absichern).
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}
