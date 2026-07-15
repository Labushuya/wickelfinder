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
  final overlay = Overlay.of(context);
  final theme = Theme.of(context);
  final isLight = theme.brightness == Brightness.light;
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 12,
      right: 12,
      // Ganz unten, knapp ueber der System-Navigationsleiste.
      bottom: bottomInset + 12,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isLight ? AppColors.primary : AppColors.darkPrimary,
              borderRadius: BorderRadius.circular(16),
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
