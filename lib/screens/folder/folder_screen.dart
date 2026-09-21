import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/release.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../add_manual/add_manual_screen.dart';
import '../capture/capture_screen.dart';
import '../card_detail/card_detail_screen.dart';
import '../shared/confirm_dialog.dart';
import '../shared/folder_cover.dart';
import '../shared/folder_picker_sheet.dart';

enum _ViewMode { grid, list }

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.releaseId});

  final String releaseId;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  _ViewMode _view = _ViewMode.grid;
  bool _selectMode = false;
  final Set<String> _selected = {};

  Future<void> _renameRelease(AppState state) async {
    final release = await state.collection.release(widget.releaseId);
    if (release == null) return;
    if (!mounted) return;
    final controller = TextEditingController(text: release.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename release'),
        content: TextField(controller: controller, autofocus: true),
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
    if (name != null && name.isNotEmpty) {
      await state.collection.updateRelease(release.copyWith(name: name));
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
          content: Text(
            '$verb $count card${count == 1 ? '' : 's'} to $name',
          ),
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
        final cards = snapshot.data![1] as List<TcgCard>;
        if (release == null) {
          return const Scaffold(body: Center(child: Text('Release not found')));
        }

        return Scaffold(
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
                      icon: Icon(
                        _view == _ViewMode.grid
                            ? Icons.view_list_outlined
                            : Icons.grid_view_outlined,
                      ),
                      onPressed: () => setState(
                        () => _view = _view == _ViewMode.grid
                            ? _ViewMode.list
                            : _ViewMode.grid,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectMode = true),
                      child: const Text('Select'),
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
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CaptureScreen(boundReleaseId: widget.releaseId),
                    ),
                  ),
                  child: const Icon(Icons.camera_alt),
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
              : _view == _ViewMode.grid
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 5 / 7,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, index) => _CardTile(
                    card: cards[index],
                    selectMode: _selectMode,
                    selected: _selected.contains(cards[index].id),
                    onTap: () => _onCardTap(cards[index]),
                    onLongPress: () => setState(() {
                      _selectMode = true;
                      _selected.add(cards[index].id);
                    }),
                    onToggleFavorite: () => _toggleFavorite(state, cards[index]),
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

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final TcgCard card;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
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
      ),
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
