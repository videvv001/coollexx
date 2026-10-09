import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/ai_settings.dart';
import '../../state/app_state.dart';
import '../../state/ocr_settings.dart';
import '../../state/theme_controller.dart';
import 'ai_binder_test_screen.dart';
import 'ai_scan_test_screen.dart';

/// The fourth tab. Not detailed in the design brief beyond its presence in
/// the tab bar — kept to what's actually implemented: collection totals,
/// the appearance toggle, and the standalone-storage note.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final themeController = context.watch<ThemeController>();
    final ocrSettings = context.watch<OcrSettings>();
    final aiSettings = context.watch<AiSettings>();
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
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
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
          Card(
            child: SwitchListTile(
              title: const Text('Auto-fill from photo (OCR)'),
              subtitle: const Text(
                'Suggests name, ID and language from the card photo when '
                'scanning. Turn off if you mostly collect games this app '
                "doesn't know the layout of — skips the category prompt too.",
              ),
              value: ocrSettings.enabled,
              onChanged: (v) => context.read<OcrSettings>().setEnabled(v),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI (testing)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Card recognition'),
                  const SizedBox(height: 4),
                  SegmentedButton<AiProvider>(
                    segments: [
                      for (final p in AiProvider.values)
                        ButtonSegment(
                          value: p,
                          label: Text(
                            p.hasKey ? p.label : '${p.label} (no key)',
                          ),
                        ),
                    ],
                    selected: {aiSettings.recognitionProvider},
                    onSelectionChanged: (s) => context
                        .read<AiSettings>()
                        .setRecognitionProvider(s.first),
                  ),
                  const SizedBox(height: 12),
                  const Text('Price research (live web search)'),
                  const SizedBox(height: 4),
                  SegmentedButton<AiProvider>(
                    segments: [
                      for (final p in AiProvider.values)
                        ButtonSegment(
                          value: p,
                          label: Text(
                            p.hasKey ? p.label : '${p.label} (no key)',
                          ),
                        ),
                    ],
                    selected: {aiSettings.researchProvider},
                    onSelectionChanged: (s) =>
                        context.read<AiSettings>().setResearchProvider(s.first),
                  ),
                  if (aiSettings.researchProvider == AiProvider.deepseek) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Experimental: DeepSeek's API docs say web search is "
                      'ignored. A result without proof of a live search is '
                      'rejected — DeepSeek\'s answer is still visible in the '
                      'raw response for comparison.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Try AI scan'),
              subtitle: const Text(
                'Photo → recognition → live price research. Saves nothing.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiScanTestScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.grid_view_outlined),
              title: const Text('Try AI binder scan'),
              subtitle: const Text(
                'Binder page → every card recognized at once. Saves nothing.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiBinderTestScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Everything is stored on this phone'),
            subtitle: Text(
              'No account, no server, no sync. Photos, cards and value '
              'entries all live in this app\'s own storage. Only the "Try AI '
              'scan" screens send data out: the photo to the recognition provider '
              'and the card details to OpenAI for price research.',
            ),
          ),
        ],
      ),
    );
  }
}
