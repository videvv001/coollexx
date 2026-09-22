import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/card_text_scan.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../state/ocr_settings.dart';
import '../../widgets/photo_placeholder.dart';
import '../shared/category_prompt.dart';
import '../shared/confirm_dialog.dart';
import 'assign_release_screen.dart';
import 'photo_preview_screen.dart';

/// 1a step 2 — Batch triage. Also doubles as the "sort the unsorted tray"
/// screen: without auto-match every shot lands here nameless either way, so
/// a fresh burst session and a return visit to old unsorted photos are the
/// same screen over the same underlying "no release yet" cards.
///
/// `cardIds` are already-real collection entries by the time this screen
/// opens — for a fresh burst, the camera screen commits its capture
/// session (creating them) before pushing here; see `CaptureScreen
/// ._commitSession`. This screen never creates cards itself any more, only
/// edits/bins the ones it's handed.
class BatchTriageScreen extends StatefulWidget {
  const BatchTriageScreen({
    super.key,
    required this.cardIds,
    this.boundReleaseId,
    this.useUnsortedTray = false,
  });

  final List<String> cardIds;
  final String? boundReleaseId;
  final bool useUnsortedTray;

  @override
  State<BatchTriageScreen> createState() => _BatchTriageScreenState();
}

class _BatchTriageScreenState extends State<BatchTriageScreen> {
  List<TcgCard> _cards = [];
  bool _loading = true;
  final Set<String> _scanning = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    if (widget.useUnsortedTray) {
      _cards = await state.collection.unsortedCards();
    } else {
      final loaded = <TcgCard>[];
      for (final id in widget.cardIds) {
        final card = await state.collection.card(id);
        if (card != null) loaded.add(card);
      }
      _cards = loaded;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _autoFillOcr(state);
  }

  /// The category a card's own (or the batch's bound) release
  /// *confidently* tells us — null means the batch-wide prompt in
  /// `_autoFillOcr` answers it instead. Only Pokémon/One Piece count:
  /// `others` is also what a release gets when nobody ever picked a
  /// category (the silent default at creation, and the fallback for a
  /// missing value), so treating it as an answer would mean scanning into
  /// such a folder never autofills and never even asks.
  ReleaseCategory? _knownCategoryFor(AppState state, TcgCard card) {
    final releaseId = card.releaseId ?? widget.boundReleaseId;
    if (releaseId == null) return null;
    for (final r in state.releases) {
      if (r.id == releaseId) {
        return r.category == ReleaseCategory.others ? null : r.category;
      }
    }
    return null;
  }

  TcgCard? _findCard(String id) {
    for (final c in _cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Runs OCR over every still-untitled card, one at a time, filling in
  /// name/number/language as each scan resolves — the same suggestion-only
  /// prefill the guided scan flow does, just applied to a whole
  /// burst/unsorted-tray batch instead of one card at a time. Re-checks the
  /// card right before writing back so a bin or a manual edit made while a
  /// scan was still in flight is never clobbered.
  ///
  /// Cards whose category can't already be told from a release are asked
  /// about at most once for the whole batch — see `pickOcrCategory` — not
  /// once per card, since that'd mean answering the same question dozens of
  /// times during a big burst.
  Future<void> _autoFillOcr(AppState state) async {
    if (!context.read<OcrSettings>().enabled) return;
    final ids = _cards
        .where((c) => c.isUntitled && c.thumbnailPath != null)
        .map((c) => c.id)
        .toList();
    if (ids.isEmpty) return;

    ReleaseCategory? promptedCategory;
    var asked = false;

    for (final id in ids) {
      final target = _findCard(id);
      if (target == null || !target.isUntitled || target.thumbnailPath == null) {
        continue;
      }

      var category = _knownCategoryFor(state, target);
      if (category == null) {
        if (!asked) {
          asked = true;
          if (!mounted) return;
          promptedCategory = await pickOcrCategory(context);
        }
        category = promptedCategory ?? ReleaseCategory.others;
      }
      if (category == ReleaseCategory.others) continue;

      if (!mounted) return;
      setState(() => _scanning.add(id));
      final guess = await scanCardText(target.thumbnailPath!, category);
      if (!mounted) return;
      setState(() => _scanning.remove(id));
      if (guess.name == null && guess.number == null && guess.language == null) {
        continue;
      }

      final latest = _findCard(id);
      if (latest == null || !latest.isUntitled) continue;
      final updated = latest.copyWith(
        name: guess.name,
        number: guess.number,
        language: guess.language,
      );
      await state.updateCard(updated);
      if (!mounted) return;
      final idx = _cards.indexWhere((c) => c.id == id);
      if (idx != -1) setState(() => _cards[idx] = updated);
    }
  }

  Future<void> _editRow(AppState state, TcgCard card) async {
    final nameController = TextEditingController(text: card.name ?? '');
    final numberController = TextEditingController(text: card.number ?? '');
    final rarityController = TextEditingController(text: card.rarity ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: numberController,
              decoration: const InputDecoration(labelText: 'Number'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: rarityController,
              decoration: const InputDecoration(labelText: 'Rarity'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final updated = card.copyWith(
                  name: nameController.text.trim().isEmpty
                      ? null
                      : nameController.text.trim(),
                  number: numberController.text.trim().isEmpty
                      ? null
                      : numberController.text.trim(),
                  rarity: rarityController.text.trim().isEmpty
                      ? null
                      : rarityController.text.trim(),
                );
                await state.updateCard(updated);
                if (context.mounted) Navigator.pop(context);
                final idx = _cards.indexWhere((c) => c.id == card.id);
                if (idx != -1) setState(() => _cards[idx] = updated);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _binRow(AppState state, TcgCard card) async {
    await state.deleteCard(card.id);
    setState(() => _cards.removeWhere((c) => c.id == card.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Card binned'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              final restored = await state.addCard(card);
              setState(() => _cards.add(restored));
            },
          ),
        ),
      );
  }

  Future<void> _binAll(AppState state) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Bin all?',
      message: 'Deletes all ${_cards.length} shots in this batch.',
      confirmLabel: 'Bin all',
    );
    if (!confirmed) return;
    final removed = List.of(_cards);
    await state.deleteCards(removed.map((c) => c.id).toList());
    setState(() => _cards.clear());
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
                await state.addCard(card);
              }
              setState(() => _cards = List.of(removed));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_cards.length} new cards'),
        actions: [
          TextButton(
            onPressed: _cards.isEmpty ? null : () => _binAll(state),
            child: const Text('Bin all'),
          ),
        ],
      ),
      body: _cards.isEmpty
          ? Center(
              child: Text(
                'Nothing to review',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _cards.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final card = _cards[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: GestureDetector(
                    onTap: card.thumbnailPath == null
                        ? null
                        : () async {
                            final edited = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PhotoPreviewScreen(
                                  path: card.thumbnailPath!,
                                ),
                              ),
                            );
                            if (edited == null) return;
                            final updated = card.copyWith(
                              photoPaths: [edited, ...card.photoPaths.skip(1)],
                            );
                            await state.updateCard(updated);
                            if (!mounted) return;
                            setState(() => _cards[index] = updated);
                          },
                    child: SizedBox(
                      width: 44,
                      child: PhotoPlaceholder(
                        path: card.thumbnailPath,
                        dashed: !card.hasPhoto,
                      ),
                    ),
                  ),
                  title: Text(
                    card.isUntitled
                        ? (_scanning.contains(card.id)
                              ? 'Scanning…'
                              : 'untitled — tap to name')
                        : card.name!,
                  ),
                  subtitle: Text(
                    [
                      if (card.number != null) '#${card.number}',
                      if (card.rarity != null) card.rarity!,
                    ].join(' · '),
                  ),
                  onTap: () => _editRow(state, card),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _binRow(state, card),
                  ),
                );
              },
            ),
      bottomNavigationBar: _cards.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignReleaseScreen(
                          cardIds: _cards.map((c) => c.id).toList(),
                          initialReleaseId: widget.boundReleaseId,
                        ),
                      ),
                    ),
                    child: Text('Assign ${_cards.length} cards →'),
                  ),
                ),
              ),
            ),
    );
  }
}
