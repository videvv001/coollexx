import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/photo_store.dart';
import '../../models/card_language.dart';
import '../../models/release.dart';
import '../../models/release_category.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../capture/batch_triage_screen.dart';
import '../capture/capture_screen.dart';
import '../folder/folder_screen.dart';
import '../search/search_screen.dart';
import '../shared/photo_editor_screen.dart';
import '../shared/photo_source_sheet.dart';
import '../empty/empty_first_run.dart';

enum _SortMode { recent, alpha, value }

enum _AddAction { newRelease, takePhoto, uploadGallery }

extension on _SortMode {
  String get label => switch (this) {
    _SortMode.recent => 'Recent',
    _SortMode.alpha => 'A–Z',
    _SortMode.value => 'Value',
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _SortMode _sort = _SortMode.recent;
  bool _forceShowGrid = false;
  final Map<String, int> _cardCounts = {};
  String? _editHintReleaseId;

  Future<void> _loadCounts(AppState state) async {
    for (final release in state.releases) {
      _cardCounts[release.id] = await state.collection.cardCountInRelease(
        release.id,
      );
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
    var category = ReleaseCategory.others;
    CardLanguage? language;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New release folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'e.g. Paldea Evolved',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReleaseCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in ReleaseCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) =>
                    setDialogState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CardLanguage?>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final l in CardLanguage.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: (v) => setDialogState(() => language = v),
              ),
            ],
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
      ),
    );
    if (name != null && name.isNotEmpty) {
      final release = await state.createRelease(name, category: category);
      if (language != null) {
        await state.collection.updateRelease(
          release.copyWith(language: language),
        );
        await state.refresh();
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FolderScreen(releaseId: release.id)),
      );
    }
  }

  Future<void> _editRelease(AppState state, Release release) async {
    final controller = TextEditingController(text: release.name);
    var coverPhotoPath = release.coverPhotoPath;
    var language = release.language;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final sourcePath = await pickPhotoSource(context);
                  if (sourcePath == null || !context.mounted) return;
                  final editedPath = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoEditorScreen(
                        sourcePath: sourcePath,
                        aspectRatio: release.coverPortrait ? 5 / 7 : 4 / 3,
                        title: 'Cover photo',
                      ),
                    ),
                  );
                  if (editedPath != null) {
                    setDialogState(() => coverPhotoPath = editedPath);
                  }
                },
                child: SizedBox(
                  width: 100,
                  child: PhotoPlaceholder(
                    path: coverPhotoPath,
                    aspectRatio: release.coverPortrait ? 5 / 7 : 4 / 3,
                    icon: Icons.folder_outlined,
                    borderRadius: 10,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CardLanguage?>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final l in CardLanguage.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: (v) => setDialogState(() => language = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final oldCoverPath = release.coverPhotoPath;
    await state.collection.updateRelease(
      release.copyWith(
        name: name,
        coverPhotoPath: coverPhotoPath,
        language: language,
        clearLanguage: language == null,
      ),
    );
    if (coverPhotoPath != oldCoverPath && oldCoverPath != null) {
      await PhotoStore.instance.delete(oldCoverPath);
    }
    await state.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _pickFromGallery(AppState state) async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BatchTriageScreen(shotPaths: files.map((f) => f.path).toList()),
      ),
    );
  }

  Future<void> _openSortMenu() async {
    final chosen = await showModalBottomSheet<_SortMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in _SortMode.values)
              ListTile(
                title: Text(mode.label),
                trailing: mode == _sort
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  Future<void> _openAddMenu(AppState state) async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New release folder'),
              onTap: () => Navigator.pop(context, _AddAction.newRelease),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, _AddAction.takePhoto),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload from gallery'),
              onTap: () => Navigator.pop(context, _AddAction.uploadGallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AddAction.newRelease:
        _newRelease(state);
        break;
      case _AddAction.takePhoto:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CaptureScreen()),
        );
        break;
      case _AddAction.uploadGallery:
        _pickFromGallery(state);
        break;
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
            onPressed: () => _openAddMenu(state),
            child: const Icon(Icons.add),
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
                      child: IconButton.filledTonal(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.search),
                        tooltip: 'Search',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IconButton.filledTonal(
                        onPressed: _openSortMenu,
                        icon: const Icon(Icons.swap_vert),
                        tooltip: 'Sort',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IconButton.filledTonal(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(openFilter: true),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        tooltip: 'Filter',
                      ),
                    ),
                  ],
                ),
                if (state.unsortedCount > 0) ...[
                  const SizedBox(height: 12),
                  _UnsortedTrayBanner(count: state.unsortedCount),
                ],
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
                    return _ReleaseTile(
                      release: release,
                      cardCount: cards,
                      showEditIcon: _editHintReleaseId == release.id,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FolderScreen(releaseId: release.id),
                        ),
                      ),
                      onLongPress: () =>
                          setState(() => _editHintReleaseId = release.id),
                      onEdit: () {
                        setState(() => _editHintReleaseId = null);
                        _editRelease(state, release);
                      },
                    );
                  },
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
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    this.showEditIcon = false,
  });

  final Release release;
  final int cardCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final bool showEditIcon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoPlaceholder(
                path: release.coverPhotoPath,
                aspectRatio: release.coverPortrait ? 5 / 7 : 4 / 3,
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
                '$cardCount cards',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (showEditIcon)
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onEdit,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.edit, size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
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
