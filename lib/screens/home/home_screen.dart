import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/release.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../capture/capture_screen.dart';
import '../folder/folder_screen.dart';
import '../search/search_screen.dart';
import '../empty/empty_first_run.dart';

enum _SortMode { recent, alpha, value }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _SortMode _sort = _SortMode.recent;
  bool _forceShowGrid = false;
  final Map<String, int> _cardCounts = {};
  final Map<String, int> _subFolderCounts = {};

  Future<void> _loadCounts(AppState state) async {
    for (final release in state.releases) {
      _cardCounts[release.id] = await state.collection.cardCountInRelease(
        release.id,
      );
      _subFolderCounts[release.id] = await state.collection
          .subFolderCountInRelease(release.id);
    }
  }

  List<Release> _sorted(List<Release> releases) {
    final list = [...releases];
    switch (_sort) {
      case _SortMode.recent:
        list.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
        break;
      case _SortMode.alpha:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case _SortMode.value:
        list.sort(
          (a, b) => (_cardCounts[b.id] ?? 0).compareTo(_cardCounts[a.id] ?? 0),
        );
        break;
    }
    return list;
  }

  Future<void> _newRelease(AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New release folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Paldea Evolved'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final release = await state.createRelease(name);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FolderScreen(releaseId: release.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_forceShowGrid &&
        state.totalCards == 0 &&
        state.unsortedCount == 0 &&
        state.releases.isEmpty) {
      return EmptyFirstRunScreen(
        onBrowseReleases: state.releases.isEmpty
            ? null
            : () => setState(() => _forceShowGrid = true),
      );
    }

    return FutureBuilder<void>(
      future: _loadCounts(state),
      builder: (context, snapshot) {
        final releases = _sorted(state.releases);
        return Scaffold(
          appBar: AppBar(
            title: const Text('My collection'),
            centerTitle: false,
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CaptureScreen()),
            ),
            child: const Icon(Icons.camera_alt),
          ),
          body: RefreshIndicator(
            onRefresh: state.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                Text(
                  '${state.totalCards} cards · ${state.releases.length} releases · '
                  '\$${state.totalValue.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        readOnly: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search your collection',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchScreen(openFilter: true),
                        ),
                      ),
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                if (state.unsortedCount > 0) ...[
                  const SizedBox(height: 12),
                  _UnsortedTrayBanner(count: state.unsortedCount),
                ],
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Recent'),
                        selected: _sort == _SortMode.recent,
                        onSelected: (_) =>
                            setState(() => _sort = _SortMode.recent),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('A–Z'),
                        selected: _sort == _SortMode.alpha,
                        onSelected: (_) =>
                            setState(() => _sort = _SortMode.alpha),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Value'),
                        selected: _sort == _SortMode.value,
                        onSelected: (_) =>
                            setState(() => _sort = _SortMode.value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: releases.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final release = releases[index];
                    final cards = _cardCounts[release.id] ?? 0;
                    final subFolders = _subFolderCounts[release.id] ?? 0;
                    return _ReleaseTile(
                      release: release,
                      cardCount: cards,
                      subFolderCount: subFolders,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FolderScreen(releaseId: release.id),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _newRelease(state),
                    icon: const Icon(Icons.add),
                    label: const Text('New release folder'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.cardCount,
    required this.subFolderCount,
    required this.onTap,
  });

  final Release release;
  final int cardCount;
  final int subFolderCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = subFolderCount > 0
        ? '$cardCount cards · $subFolderCount sub-folders'
        : '$cardCount cards';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoPlaceholder(
            path: release.coverPhotoPath,
            aspectRatio: 4 / 3,
            icon: Icons.folder_outlined,
            borderRadius: 12,
          ),
          const SizedBox(height: 8),
          Text(
            release.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            meta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsortedTrayBanner extends StatelessWidget {
  const _UnsortedTrayBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Sorting the tray reuses the assign-to-release step of capture.
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CaptureScreen(startAtUnsortedTray: true),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.photo_library_outlined,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count unsorted photos',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Shot recently, no release yet',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CaptureScreen(startAtUnsortedTray: true),
                  ),
                ),
                child: const Text('Sort'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
