import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/photo_store.dart';
import '../../models/release.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../add_manual/add_manual_screen.dart';
import '../capture/batch_triage_screen.dart';
import '../capture/capture_route.dart';
import '../capture/capture_screen.dart';
import '../capture/live_framing.dart';
import '../capture/name_tag_file_screen.dart';
import '../card_detail/card_detail_screen.dart';
import '../shared/confirm_dialog.dart';
import '../shared/folder_cover.dart';
import '../shared/folder_picker_sheet.dart';
import '../shared/photo_editor_screen.dart';
import 'folder_sort.dart';

enum _ViewMode { grid, gridDetails, list }

// One preference across every folder (there's no per-folder view-mode
// storage in this app — see `_displayModePrefsKey` in home_screen.dart for
// the same pattern applied to the release grid's own display mode).
const _viewModePrefsKey = 'folder_view_mode';

extension on _ViewMode {
  IconData get icon => switch (this) {
    _ViewMode.grid => Icons.grid_view_outlined,
    _ViewMode.gridDetails => Icons.view_module_outlined,
    _ViewMode.list => Icons.view_list_outlined,
  };

  String get nextLabel => switch (this) {
    _ViewMode.grid => 'Switch to grid with details',
    _ViewMode.gridDetails => 'Switch to list',
    _ViewMode.list => 'Switch to grid',
  };

  _ViewMode get next => switch (this) {
    _ViewMode.grid => _ViewMode.gridDetails,
    _ViewMode.gridDetails => _ViewMode.list,
    _ViewMode.list => _ViewMode.grid,
  };
}

enum _AddAction { takePhoto, uploadImage, addWithoutImage }

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.releaseId});

  final String releaseId;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  static const _uuid = Uuid();
  _ViewMode _view = _ViewMode.grid;
  bool _selectMode = false;
  final Set<String> _selected = {};
  FolderSortType _sortType = FolderSortType.id;
  SortDirection _sortDirection = SortDirection.ascending;

  String get _sortPrefsKey => 'folder_sort_${widget.releaseId}';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadSortPref();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_viewModePrefsKey);
    if (saved == null || !mounted) return;
    setState(() => _view = _ViewMode.values.byName(saved));
  }

  Future<void> _cycleViewMode() async {
    setState(() => _view = _view.next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModePrefsKey, _view.name);
  }

  /// Sort choice is stored per folder (keyed by `releaseId`) rather than as
  /// one app-wide preference, so different releases can each remember their
  /// own sort — see `_viewModePrefsKey` above for the one global preference
  /// this deliberately does NOT follow.
  Future<void> _loadSortPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sortPrefsKey);
    if (saved == null || !mounted) return;
    final parts = saved.split('|');
    if (parts.length != 2) return;
    final type = FolderSortType.values.asNameMap()[parts[0]];
    final direction = SortDirection.values.asNameMap()[parts[1]];
    if (type == null || direction == null) return;
    setState(() {
      _sortType = type;
      _sortDirection = direction;
    });
  }

  Future<void> _openSortMenu() async {
    final result = await showModalBottomSheet<(FolderSortType, SortDirection)>(
      context: context,
      builder: (context) =>
          _FolderSortSheet(type: _sortType, direction: _sortDirection),
    );
    if (result == null) return;
    setState(() {
      _sortType = result.$1;
      _sortDirection = result.$2;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sortPrefsKey,
      '${_sortType.name}|${_sortDirection.name}',
    );
  }

  Future<void> _openAddMenu() async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, _AddAction.takePhoto),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload image'),
              onTap: () => Navigator.pop(context, _AddAction.uploadImage),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add without image'),
              onTap: () => Navigator.pop(context, _AddAction.addWithoutImage),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AddAction.takePhoto:
        Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: captureRouteName),
            builder: (_) => CaptureScreen(boundReleaseId: widget.releaseId),
          ),
        );
        break;
      case _AddAction.uploadImage:
        _uploadImage();
        break;
      case _AddAction.addWithoutImage:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddManualScreen(releaseId: widget.releaseId),
          ),
        );
        break;
    }
  }

  /// Gallery image(s), pre-filed into this folder. One pick keeps the
  /// per-card path — crop editor, then the same name/tag/file screen the
  /// guided camera scan ends on. Several picks route to batch triage
  /// instead, the same screen a burst lands on: cropping and naming a
  /// dozen cards one modal at a time is the thing triage exists to avoid.
  /// Both destinations already run OCR autofill, so neither needs its own.
  Future<void> _uploadImage() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;

    if (files.length == 1) {
      final cropped = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoEditorScreen(
            sourcePath: files.first.path,
            aspectRatio: kCardAspect,
            title: 'Crop photo',
          ),
        ),
      );
      if (cropped == null || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: captureRouteName),
          builder: (_) => NameTagFileScreen(
            photoPaths: [cropped],
            boundReleaseId: widget.releaseId,
          ),
        ),
      );
      return;
    }

    final state = context.read<AppState>();
    final cardIds = <String>[];
    for (final file in files) {
      // Copied into the app's own storage rather than referencing the
      // picker's temp path, which the OS is free to reap.
      final saved = await PhotoStore.instance.save(File(file.path));
      final card = await state.addCard(
        TcgCard(
          id: _uuid.v4(),
          photoPaths: [saved],
          releaseId: widget.releaseId,
          createdAt: DateTime.now(),
        ),
      );
      cardIds.add(card.id);
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: captureRouteName),
        builder: (_) => BatchTriageScreen(
          cardIds: cardIds,
          boundReleaseId: widget.releaseId,
        ),
      ),
    );
  }

  Future<void> _renameRelease(AppState state) async {
    final release = await state.collection.release(widget.releaseId);
    if (release == null) return;
    if (!mounted) return;
    final controller = TextEditingController(text: release.name);
    var category = release.category;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rename release'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, autofocus: true),
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
            ],
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
      ),
    );
    if (name != null && name.isNotEmpty) {
      await state.collection.updateRelease(
        release.copyWith(name: name, category: category),
      );
      await state.refresh();
      setState(() {});
    }
  }

  Future<bool?> _pickCoverShape() {
    return showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cover shape'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Landscape'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Portrait'),
          ),
        ],
      ),
    );
  }

  Future<void> _setCoverPhoto(AppState state) async {
    final release = await state.collection.release(widget.releaseId);
    if (release == null || !mounted) return;
    final cards = await state.collection.cardsInRelease(widget.releaseId);
    if (!mounted) return;
    final portrait = await _pickCoverShape();
    if (portrait == null || !mounted) return;
    final otherUnset = portrait
        ? release.landscapeCoverPath == null
        : release.portraitCoverPath == null;
    final oldPath = portrait
        ? release.portraitCoverPath
        : release.landscapeCoverPath;
    final result = await pickCoverWithAutoFill(
      context,
      aspectRatio: portrait ? kPortraitCoverAspect : kLandscapeCoverAspect,
      title: 'Cover photo',
      otherAspectRatio: otherUnset
          ? (portrait ? kLandscapeCoverAspect : kPortraitCoverAspect)
          : null,
      allowExistingCardPhoto: true,
      releaseCards: cards,
      currentImagePath: oldPath,
    );
    if (result == null) return;
    final oldOtherPath = portrait
        ? release.landscapeCoverPath
        : release.portraitCoverPath;
    final newLandscape = portrait
        ? (result.autoOtherPath ?? release.landscapeCoverPath)
        : result.croppedPath;
    final newPortrait = portrait
        ? result.croppedPath
        : (result.autoOtherPath ?? release.portraitCoverPath);
    await state.collection.updateRelease(
      release.copyWith(
        landscapeCoverPath: newLandscape,
        portraitCoverPath: newPortrait,
      ),
    );
    await deleteCoverIfOrphaned(oldPath, [
      release.coverPhotoPath,
      newLandscape,
      newPortrait,
    ]);
    if (result.autoOtherPath != null) {
      await deleteCoverIfOrphaned(oldOtherPath, [
        release.coverPhotoPath,
        newLandscape,
        newPortrait,
      ]);
    }
    await state.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _deleteRelease(
    AppState state,
    Release release,
    List<TcgCard> cards,
  ) async {
    final cardCount = cards.fold<int>(0, (sum, c) => sum + c.copies);
    final deleted = await confirmAndDeleteRelease(
      context,
      state,
      release,
      cardCount: cardCount,
    );
    if (deleted && mounted) Navigator.pop(context);
  }

  Future<void> _bulkMove(AppState state) async {
    final destination = await pickDestinationFolder(
      context,
      state: state,
      title: 'Move to folder',
      excludeReleaseId: widget.releaseId,
    );
    if (destination == null) return;
    await state.moveCards(_selected.toList(), releaseId: destination);
    final count = _selected.length;
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    _showMoveCopyFeedback('Moved', count, destination, state);
  }

  Future<void> _bulkCopy(AppState state) async {
    final destination = await pickDestinationFolder(
      context,
      state: state,
      title: 'Copy to folder',
    );
    if (destination == null) return;
    await state.copyCards(_selected.toList(), releaseId: destination);
    final count = _selected.length;
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    _showMoveCopyFeedback('Copied', count, destination, state);
  }

  void _showMoveCopyFeedback(
    String verb,
    int count,
    String destinationReleaseId,
    AppState state,
  ) {
    if (!mounted) return;
    final name = state.releases
        .firstWhere((r) => r.id == destinationReleaseId)
        .name;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('$verb $count card${count == 1 ? '' : 's'} to $name'),
        ),
      );
  }

  Future<void> _bulkTrade(AppState state) async {
    await state.collection.setTradeFlags(_selected.toList(), forTrade: true);
    await state.refresh();
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  Future<void> _bulkTag(AppState state) async {
    final rarity = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Tag rarity'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. Holo Rare'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (rarity != null && rarity.isNotEmpty) {
      for (final id in _selected) {
        final card = await state.collection.card(id);
        if (card != null) {
          await state.collection.updateCard(card.copyWith(rarity: rarity));
        }
      }
      await state.refresh();
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
    }
  }

  Future<void> _bulkBin(AppState state) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Bin ${_selected.length} cards?',
      message: 'This deletes them and their value history.',
      confirmLabel: 'Bin',
    );
    if (!confirmed) return;
    final ids = _selected.toList();
    final removed = <TcgCard>[];
    for (final id in ids) {
      final card = await state.collection.card(id);
      if (card != null) removed.add(card);
    }
    await state.deleteCards(ids);
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Binned ${removed.length} cards'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final card in removed) {
                await state.collection.createCard(card);
              }
              await state.refresh();
              if (mounted) setState(() {});
            },
          ),
        ),
      );
  }

  Future<void> _toggleFavorite(AppState state, TcgCard card) async {
    await state.updateCard(card.copyWith(isFavorite: !card.isFavorite));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder(
      future: Future.wait([
        state.collection.release(widget.releaseId),
        state.collection.cardsInRelease(widget.releaseId),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final release = snapshot.data![0] as Release?;
        final rawCards = snapshot.data![1] as List<TcgCard>;
        if (release == null) {
          return const Scaffold(body: Center(child: Text('Release not found')));
        }
        final cards = sortFolderCards(
          rawCards,
          type: _sortType,
          direction: _sortDirection,
          category: release.category,
        );

        return PopScope(
          canPop: !_selectMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            setState(() {
              _selectMode = false;
              _selected.clear();
            });
          },
          child: Scaffold(
            appBar: AppBar(
              leading: _selectMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _selectMode = false;
                        _selected.clear();
                      }),
                    )
                  : const BackButton(),
              title: Text(
                _selectMode ? '${_selected.length} selected' : release.name,
              ),
              actions: _selectMode
                  ? [
                      TextButton(
                        onPressed: () => setState(
                          () => _selected.addAll(cards.map((c) => c.id)),
                        ),
                        child: Text('Select all ${cards.length}'),
                      ),
                    ]
                  : [
                      IconButton(
                        icon: const Icon(Icons.swap_vert),
                        tooltip: 'Sort',
                        onPressed: _openSortMenu,
                      ),
                      IconButton(
                        icon: Icon(_view.icon),
                        tooltip: _view.nextLabel,
                        onPressed: _cycleViewMode,
                      ),
                      PopupMenuButton<String>(
                        onSelected: (choice) {
                          if (choice == 'cover') _setCoverPhoto(state);
                          if (choice == 'rename') _renameRelease(state);
                          if (choice == 'delete') {
                            _deleteRelease(state, release, cards);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'cover',
                            child: Text('Set cover photo'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
            ),
            floatingActionButton: _selectMode
                ? null
                : FloatingActionButton(
                    onPressed: _openAddMenu,
                    child: const Icon(Icons.add),
                  ),
            bottomNavigationBar: _selectMode && _selected.isNotEmpty
                ? BottomAppBar(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: () => _bulkMove(state),
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: const Text('Move'),
                        ),
                        TextButton.icon(
                          onPressed: () => _bulkCopy(state),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copy'),
                        ),
                        TextButton.icon(
                          onPressed: () => _bulkTag(state),
                          icon: const Icon(Icons.label_outline),
                          label: const Text('Tag'),
                        ),
                        TextButton.icon(
                          onPressed: () => _bulkTrade(state),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Trade'),
                        ),
                        TextButton.icon(
                          onPressed: () => _bulkBin(state),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Bin'),
                        ),
                      ],
                    ),
                  )
                : null,
            body: cards.isEmpty
                ? _EmptyFolder(releaseId: widget.releaseId)
                : _view != _ViewMode.list
                ? GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: _view == _ViewMode.gridDetails
                          ? 5 / 8.6
                          : 5 / 7,
                    ),
                    itemCount: cards.length,
                    itemBuilder: (context, index) => _CardTile(
                      card: cards[index],
                      selectMode: _selectMode,
                      selected: _selected.contains(cards[index].id),
                      showDetails: _view == _ViewMode.gridDetails,
                      onTap: () => _onCardTap(cards[index]),
                      onLongPress: () => setState(() {
                        _selectMode = true;
                        _selected.add(cards[index].id);
                      }),
                      onToggleFavorite: () =>
                          _toggleFavorite(state, cards[index]),
                    ),
                  )
                : ListView.builder(
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 40,
                          child: PhotoPlaceholder(
                            path: card.thumbnailPath,
                            dashed: !card.hasPhoto,
                          ),
                        ),
                        title: Text(card.isUntitled ? 'Untitled' : card.name!),
                        subtitle: Text(
                          [
                            if (card.number != null) '#${card.number}',
                            'x${card.copies}',
                          ].join(' · '),
                        ),
                        selected: _selected.contains(card.id),
                        onTap: () => _onCardTap(card),
                        onLongPress: () => setState(() {
                          _selectMode = true;
                          _selected.add(card.id);
                        }),
                        trailing: IconButton(
                          icon: Icon(
                            card.isFavorite ? Icons.star : Icons.star_border,
                            color: card.isFavorite
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          onPressed: () => _toggleFavorite(state, card),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _onCardTap(TcgCard card) {
    if (_selectMode) {
      setState(() {
        if (_selected.contains(card.id)) {
          _selected.remove(card.id);
        } else {
          _selected.add(card.id);
        }
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id)),
      ).then((_) => setState(() {}));
    }
  }
}

/// Sort-by / order picker for a folder's cards. Order only applies to ID
/// (Favorite/Recent/Rarity each have one fixed, well-defined direction), so
/// it's only shown once ID is selected.
class _FolderSortSheet extends StatefulWidget {
  const _FolderSortSheet({required this.type, required this.direction});

  final FolderSortType type;
  final SortDirection direction;

  @override
  State<_FolderSortSheet> createState() => _FolderSortSheetState();
}

class _FolderSortSheetState extends State<_FolderSortSheet> {
  late FolderSortType _type = widget.type;
  late SortDirection _direction = widget.direction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Sort by',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            RadioGroup<FolderSortType>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v!),
              child: Column(
                children: [
                  for (final t in FolderSortType.values)
                    RadioListTile<FolderSortType>(
                      title: Text(t.label),
                      value: t,
                    ),
                ],
              ),
            ),
            if (_type == FolderSortType.id) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Order',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              RadioGroup<SortDirection>(
                groupValue: _direction,
                onChanged: (v) => setState(() => _direction = v!),
                child: Column(
                  children: [
                    RadioListTile<SortDirection>(
                      title: const Text('Ascending'),
                      value: SortDirection.ascending,
                    ),
                    RadioListTile<SortDirection>(
                      title: const Text('Descending'),
                      value: SortDirection.descending,
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, (_type, _direction)),
                  child: const Text('Apply'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.selectMode,
    required this.selected,
    required this.showDetails,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final TcgCard card;
  final bool selectMode;
  final bool selected;
  final bool showDetails;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = Stack(
      children: [
        Positioned.fill(
          child: PhotoPlaceholder(
            path: card.thumbnailPath,
            dashed: !card.hasPhoto,
            borderRadius: 6,
          ),
        ),
        if (!selectMode)
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
                  card.isFavorite ? Icons.star : Icons.star_border,
                  size: 14,
                  color: card.isFavorite ? Colors.amber : Colors.white,
                ),
              ),
            ),
          ),
        if (selectMode)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? scheme.primary
                    : Colors.black.withValues(alpha: 0.3),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        if (selected)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );

    // Name (left) / ID (right) below the image — kept out of the Stack
    // above so it can never overlap the favorite star or selection badge.
    final content = !showDetails
        ? image
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: image),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.isUntitled ? 'Untitled' : card.name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (card.number != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      card.number!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: content,
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.releaseId});

  final String releaseId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('No cards yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Scan into a slot, or shoot a burst and assign the lot to this '
            'release afterwards.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: captureRouteName),
                builder: (_) => CaptureScreen(boundReleaseId: releaseId),
              ),
            ),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan into this release'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddManualScreen(releaseId: releaseId),
              ),
            ),
            child: const Text('Add without a photo'),
          ),
        ],
      ),
    );
  }
}
