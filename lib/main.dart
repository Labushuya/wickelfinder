import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/map/presentation/map_screen.dart';

void main() {
  runApp(const ProviderScope(child: WickelfinderApp()));
}

class WickelfinderApp extends StatelessWidget {
  const WickelfinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wickelfinder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const MapScreen(),
    );
  }
}
