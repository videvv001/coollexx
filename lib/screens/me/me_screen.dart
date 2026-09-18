import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

/// The fourth tab. Not detailed in the design brief beyond its presence in
/// the tab bar — kept to what's actually implemented: collection totals and
/// the standalone-storage note, no settings that don't exist yet.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
