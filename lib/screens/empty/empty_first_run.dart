import 'package:flutter/material.dart';

import '../add_manual/add_manual_screen.dart';
import '../capture/capture_screen.dart';

/// 1d screen 8 — shown on Home before the first card exists anywhere.
class EmptyFirstRunScreen extends StatelessWidget {
  const EmptyFirstRunScreen({super.key, this.onBrowseReleases});

  /// When null (no releases exist yet either), the "Browse releases" action
  /// is omitted rather than pointing at something that isn't there yet.
  final VoidCallback? onBrowseReleases;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My collection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 196,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.style_outlined,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start with one card',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Photograph what you own. Releases and sub-folders can come '
              'later — a card only needs a folder when you want one.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CaptureScreen()),
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan a card'),
            ),
            if (onBrowseReleases != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onBrowseReleases,
                child: const Text('Browse releases'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddManualScreen()),
              ),
              child: const Text('Add without a photo'),
            ),
          ],
        ),
      ),
    );
  }
}
