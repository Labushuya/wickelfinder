import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'features/map/presentation/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Backend nur initialisieren, wenn per --dart-define konfiguriert.
  // Ohne Konfiguration laeuft die App als reine (Offline-taugliche) Kartenansicht.
  await SupabaseInit.ensureInitialized();
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
