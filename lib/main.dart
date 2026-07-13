import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/map/presentation/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Backend nur initialisieren, wenn per --dart-define konfiguriert.
  // Ohne Konfiguration laeuft die App als reine (Offline-taugliche) Kartenansicht.
  await SupabaseInit.ensureInitialized();
  runApp(const ProviderScope(child: WickelfinderApp()));
}

class WickelfinderApp extends ConsumerWidget {
  const WickelfinderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Wickelfinder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const MapScreen(),
    );
  }
}
