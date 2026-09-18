import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/release.dart';
import '../../state/app_state.dart';
import '../folder/folder_screen.dart';

enum _SetSort { completion, recent, alpha }

/// 1d screen 4 — Sets. No official checklist is ever bundled (the app has
/// no card database, by design — see the handoff's "Cut" section), so every
/// release runs in the degraded path from the spec: a user-declared total
/// cards count drives the bar, and the numbered missing-slot grid is
/// dropped rather than faked.
class SetsScreen extends StatefulWidget {
  const SetsScreen({super.key});

  @override
  State<SetsScreen> createState() => _SetsScreenState();
}

class _SetsScreenState extends State<SetsScreen> {
  _SetSort _sort = _SetSort.completion;
  final Map<String, int> _owned = {};

  Future<void> _loadOwned(AppState state) async {
    for (final r in state.releases) {
      _owned[r.id] = await state.collection.cardCountInRelease(r.id);
    }
  }

  Future<void> _setTarget(AppState state, Release release) async {
    final controller = TextEditingController(
      text: release.totalCardsInSet?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set size'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'This set has… cards'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final total = int.tryParse(value ?? '');
    if (total != null) {
      await state.collection.updateRelease(
        release.copyWith(totalCardsInSet: total),
      );
      await state.refresh();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder<void>(
      future: _loadOwned(state),
      builder: (context, snapshot) {
        final releases = [...state.releases];
        switch (_sort) {
          case _SetSort.completion:
            releases.sort((a, b) {
              final pa = a.totalCardsInSet == null
                  ? -1
                  : (_owned[a.id] ?? 0) / a.totalCardsInSet!;
              final pb = b.totalCardsInSet == null
                  ? -1
                  : (_owned[b.id] ?? 0) / b.totalCardsInSet!;
              return pb.compareTo(pa);
            });
            break;
          case _SetSort.recent:
            releases.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
            break;
          case _SetSort.alpha:
            releases.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            break;
        }
        final complete = releases.where((r) {
          final total = r.totalCardsInSet;
          return total != null && (_owned[r.id] ?? 0) >= total;
        }).length;
        final tracked = releases.where((r) => r.totalCardsInSet != null).length;

        return Scaffold(
          appBar: AppBar(title: const Text('Sets')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '$complete of $tracked complete',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_SetSort>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _SetSort.completion,
                    label: Text('Completion'),
                  ),
                  ButtonSegment(value: _SetSort.recent, label: Text('Recent')),
                  ButtonSegment(value: _SetSort.alpha, label: Text('A–Z')),
                ],
                selected: {_sort},
                onSelectionChanged: (s) => setState(() => _sort = s.first),
              ),
              const SizedBox(height: 12),
              if (releases.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No releases yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              for (final release in releases)
                _SetRow(
                  release: release,
                  owned: _owned[release.id] ?? 0,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FolderScreen(releaseId: release.id),
                    ),
                  ),
                  onSetTarget: () => _setTarget(state, release),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.release,
    required this.owned,
    required this.onTap,
    required this.onSetTarget,
  });

  final Release release;
  final int owned;
  final VoidCallback onTap;
  final VoidCallback onSetTarget;

  @override
  Widget build(BuildContext context) {
    final total = release.totalCardsInSet;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        title: Text(release.name),
        subtitle: total == null
            ? const Text('No set size — tap "Set size" to track completion')
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$owned/$total'),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (owned / total).clamp(0, 1),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
        trailing: TextButton(
          onPressed: onSetTarget,
          child: Text(total == null ? 'Set size' : 'Edit'),
        ),
      ),
    );
  }
}
