import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/card_language.dart';
import '../../models/release.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../capture/batch_triage_screen.dart';
import '../capture/capture_screen.dart';
import '../folder/folder_screen.dart';
import '../search/search_screen.dart';
import '../shared/folder_cover.dart';
import '../empty/empty_first_run.dart';

enum _SortMode { recent, alpha, value, favorite }

enum _DisplayMode { landscape, portrait }

const _displayModePrefsKey = 'collection_display_mode';

extension on _DisplayMode {
  bool get isPortrait => this == _DisplayMode.portrait;
  double get coverAspect =>
      isPortrait ? kPortraitCoverAspect : kLandscapeCoverAspect;
  IconData get icon =>
      isPortrait ? Icons.crop_landscape_outlined : Icons.crop_portrait_outlined;
  String get switchToLabel =>
      isPortrait ? 'Switch to landscape view' : 'Switch to portrait view';
}

enum _AddAction { newRelease, takePhoto, uploadGallery }

extension on _SortMode {
  String get label => switch (this) {
    _SortMode.recent => 'Recent',
    _SortMode.alpha => 'A–Z',
    _SortMode.value => 'Value',
    _SortMode.favorite => 'Favorite',
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _uuid = Uuid();
  _SortMode _sort = _SortMode.recent;
  _DisplayMode _displayMode = _DisplayMode.landscape;
  bool _forceShowGrid = false;
  final Map<String, int> _cardCounts = {};

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_displayModePrefsKey);
    if (saved == null || !mounted) return;
    setState(() => _displayMode = _DisplayMode.values.byName(saved));
  }

  Future<void> _toggleDisplayMode() async {
    setState(() {
      _displayMode = _displayMode.isPortrait
          ? _DisplayMode.landscape
          : _DisplayMode.portrait;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModePrefsKey, _displayMode.name);
  }

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
      case _SortMode.favorite:
        list.sort((a, b) {
          if (a.isFavorite != b.isFavorite) {
            return a.isFavorite ? -1 : 1;
          }
          return b.dateCreated.compareTo(a.dateCreated);
        });
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
    var language = release.language;
    var landscapePath = release.displayLandscapeCover;
    var portraitPath = release.displayPortraitCover;

    Future<void> pickCover(
      StateSetter setDialogState, {
      required bool portrait,
    }) async {
      final otherUnset = portrait
          ? landscapePath == null
          : portraitPath == null;
      final result = await pickCoverWithAutoFill(
        context,
        aspectRatio: portrait ? kPortraitCoverAspect : kLandscapeCoverAspect,
        title: portrait ? 'Portrait cover' : 'Landscape cover',
        otherAspectRatio: otherUnset
            ? (portrait ? kLandscapeCoverAspect : kPortraitCoverAspect)
            : null,
        currentImagePath: portrait ? portraitPath : landscapePath,
      );
      if (result == null || !context.mounted) return;
      setDialogState(() {
        if (portrait) {
          portraitPath = result.croppedPath;
          landscapePath = result.autoOtherPath ?? landscapePath;
        } else {
          landscapePath = result.croppedPath;
          portraitPath = result.autoOtherPath ?? portraitPath;
        }
      });
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit folder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CoverPickerTile(
                        label: 'Landscape',
                        path: landscapePath,
                        aspectRatio: kLandscapeCoverAspect,
                        onTap: () => pickCover(setDialogState, portrait: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CoverPickerTile(
                        label: 'Portrait',
                        path: portraitPath,
                        aspectRatio: kPortraitCoverAspect,
                        onTap: () => pickCover(setDialogState, portrait: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
    final oldLandscapePath = release.landscapeCoverPath;
    final oldPortraitPath = release.portraitCoverPath;
    await state.collection.updateRelease(
      release.copyWith(
        name: name,
        language: language,
        clearLanguage: language == null,
        landscapeCoverPath: landscapePath,
        clearLandscapeCover: landscapePath == null,
        portraitCoverPath: portraitPath,
        clearPortraitCover: portraitPath == null,
      ),
    );
    await deleteCoverIfOrphaned(oldLandscapePath, [
      release.coverPhotoPath,
      landscapePath,
      portraitPath,
    ]);
    await deleteCoverIfOrphaned(oldPortraitPath, [
      release.coverPhotoPath,
      landscapePath,
      portraitPath,
    ]);
    await state.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _openReleaseMenu(AppState state, Release release) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editRelease(state, release);
        break;
      case 'delete':
        await _deleteRelease(state, release);
        break;
    }
  }

  Future<void> _toggleFavorite(AppState state, Release release) async {
    await state.collection.updateRelease(
      release.copyWith(isFavorite: !release.isFavorite),
    );
    await state.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _deleteRelease(AppState state, Release release) async {
    final deleted = await confirmAndDeleteRelease(
      context,
      state,
      release,
      cardCount: _cardCounts[release.id] ?? 0,
    );
    if (deleted && mounted) setState(() {});
  }

  Future<void> _pickFromGallery(AppState state) async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    // Gallery picks are created immediately, not staged through a
    // CaptureSession — there's no incremental in-progress shoot to protect
    // here, the whole batch is already picked in one step.
    final cardIds = <String>[];
    for (final file in files) {
      final card = await state.addCard(
        TcgCard(
          id: _uuid.v4(),
          photoPaths: [file.path],
          createdAt: DateTime.now(),
        ),
      );
      cardIds.add(card.id);
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BatchTriageScreen(cardIds: cardIds)),
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
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
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
                            builder: (_) =>
                                const SearchScreen(openFilter: true),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        tooltip: 'Filter',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IconButton.filledTonal(
                        onPressed: _toggleDisplayMode,
                        icon: Icon(_displayMode.icon),
                        tooltip: _displayMode.switchToLabel,
                      ),
                    ),
                  ],
                ),
                if (state.unsortedCount > 0) ...[
                  const SizedBox(height: 12),
                  _UnsortedTrayBanner(count: state.unsortedCount),
                ],
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const crossAxisCount = 2;
                    const spacing = 16.0;
                    // Fixed budget for the name (1 line) + card count (1
                    // line) block below the cover, so the grid's aspect
                    // ratio can be derived purely from geometry rather than
                    // measuring text — keeping every cell the same height
                    // regardless of image content, which is what actually
                    // prevents cells from overlapping the row below.
                    const textBlockHeight = 46.0;
                    final itemWidth =
                        (constraints.maxWidth -
                            spacing * (crossAxisCount - 1)) /
                        crossAxisCount;
                    final itemHeight =
                        itemWidth / _displayMode.coverAspect + textBlockHeight;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: releases.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: itemWidth / itemHeight,
                      ),
                      itemBuilder: (context, index) {
                        final release = releases[index];
                        final cards = _cardCounts[release.id] ?? 0;
                        return _ReleaseTile(
                          release: release,
                          displayMode: _displayMode,
                          cardCount: cards,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FolderScreen(releaseId: release.id),
                            ),
                          ),
                          onLongPress: () => _openReleaseMenu(state, release),
                          onToggleFavorite: () =>
                              _toggleFavorite(state, release),
                        );
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
    required this.displayMode,
    required this.cardCount,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final Release release;
  final _DisplayMode displayMode;
  final int cardCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              PhotoPlaceholder(
                path: displayMode.isPortrait
                    ? release.displayPortraitCover
                    : release.displayLandscapeCover,
                aspectRatio: displayMode.coverAspect,
                icon: Icons.folder_outlined,
                borderRadius: 12,
              ),
              // Nested GestureDetector so tapping the star doesn't also fire
              // the InkWell's onTap and open the folder — the same pattern
              // the collection-card favorite star uses in FolderScreen.
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: onToggleFavorite,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black38,
                    ),
                    child: Icon(
                      release.isFavorite ? Icons.star : Icons.star_border,
                      size: 14,
                      color: release.isFavorite ? Colors.amber : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
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
    );
  }
}

/// One cover preview + label inside the Edit Folder dialog. Shown at its
/// real aspect ratio so landscape and portrait are visually obvious, with a
/// small edit badge signalling it's tappable to change or re-crop.
class _CoverPickerTile extends StatelessWidget {
  const _CoverPickerTile({
    required this.label,
    required this.path,
    required this.aspectRatio,
    required this.onTap,
  });

  final String label;
  final String? path;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              PhotoPlaceholder(
                path: path,
                aspectRatio: aspectRatio,
                icon: Icons.folder_outlined,
                borderRadius: 10,
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(
          path == null ? 'Change' : 'Change / Adjust',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
