import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Zeigt die gebuendelte Datenschutzerklaerung (PRIVACY.md) als lesbaren Text.
/// Bewusst ohne Markdown-Dependency — der Rohtext ist ausreichend lesbar.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutz')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString('PRIVACY.md'),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: SelectableText(
                snap.data!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          },
        ),
      ),
    );
  }
}
