import 'dart:async';

import 'package:flutter/material.dart';

/// Icon-only FloatingActionButton. Ein kurzer Tap loest [onPressed] aus.
/// Wird der Button GEHALTEN (Long-Press), faehrt das Label seitlich aus und
/// beim Loslassen wieder ein — ohne die normale Tap-Funktion zu blockieren.
class HoldToLabelFab extends StatefulWidget {
  const HoldToLabelFab({
    super.key,
    required this.icon,
    required this.label,
    required this.heroTag,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String heroTag;
  final VoidCallback onPressed;

  @override
  State<HoldToLabelFab> createState() => _HoldToLabelFabState();
}

class _HoldToLabelFabState extends State<HoldToLabelFab> {
  bool _expanded = false;
  Timer? _holdTimer;

  void _onDown() {
    // Erst nach echtem Halten (300ms) ausfahren -> Tap bleibt Tap.
    _holdTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _expanded = true);
    });
  }

  void _onUpOrCancel() {
    _holdTimer?.cancel();
    if (_expanded && mounted) setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUpOrCancel(),
      onPointerCancel: (_) => _onUpOrCancel(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: _expanded
            ? FloatingActionButton.extended(
                heroTag: widget.heroTag,
                onPressed: widget.onPressed,
                icon: Icon(widget.icon),
                label: Text(widget.label),
              )
            : FloatingActionButton(
                heroTag: widget.heroTag,
                tooltip: widget.label,
                onPressed: widget.onPressed,
                child: Icon(widget.icon),
              ),
      ),
    );
  }
}
