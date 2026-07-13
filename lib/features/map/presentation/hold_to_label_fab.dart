import 'package:flutter/material.dart';

/// Icon-only FloatingActionButton, dessen Label bei gedrueckt-halten (Touch
/// oder Maus) seitlich ausfaehrt und beim Loslassen wieder einfaehrt.
/// Ein kurzer Tap loest [onPressed] aus.
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

  void _show() => setState(() => _expanded = true);
  void _hide() => setState(() => _expanded = false);

  @override
  Widget build(BuildContext context) {
    // Bei gehaltenem Druck Label zeigen, sonst nur Icon. AnimatedSize sorgt
    // fuer sanftes Aus-/Einfahren.
    return Listener(
      onPointerDown: (_) => _show(),
      onPointerUp: (_) => _hide(),
      onPointerCancel: (_) => _hide(),
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
