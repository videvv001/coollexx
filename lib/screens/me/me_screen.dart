import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/theme_controller.dart';

/// The fourth tab. Not detailed in the design brief beyond its presence in
/// the tab bar — kept to what's actually implemented: collection totals,
/// the appearance toggle, and the standalone-storage note.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final themeController = context.watch<ThemeController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.totalCards} cards',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${state.releases.length} releases'),
                  Text(
                    'Collection value \$${state.totalValue.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('System'),
                      ),
                    ],
                    selected: {themeController.mode},
                    onSelectionChanged: (s) =>
                        context.read<ThemeController>().setMode(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Everything is stored on this phone'),
            subtitle: Text(
              'No account, no server, no sync. Photos, cards and value '
              'entries all live in this app\'s own storage.',
            ),
          ),
        ],
      ),
    );
  }
}
