import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/value_repository.dart';
import '../../models/release.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../models/value_entry.dart';
import '../../state/app_state.dart';
import '../../utils/formatting.dart';
import '../shared/confirm_dialog.dart';
import '../shared/folder_picker_sheet.dart';
import 'add_value_sheet.dart';
import 'card_image_carousel.dart';
import 'card_metadata_fields.dart';
import 'card_metadata_grid.dart';
import 'edit_card_screen.dart';
import 'value_graph.dart';
import 'value_history_screen.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  ValueRange _range = ValueRange.month;
  TcgCard? _card;
  List<ValueEntry> _entries = [];

  Future<void> _load(AppState state) async {
    final card = await state.collection.card(widget.cardId);
    final entries = await state.value.allForCard(widget.cardId);
    if (!mounted) return;
    setState(() {
      _card = card;
      _entries = entries;
    });
  }

  Future<void> _addValue(AppState state) async {
    final result = await showModalBottomSheet<({DateTime date, double amount})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddValueSheet(
        lastAmount: _entries.isEmpty ? null : _entries.last.amount,
      ),
    );
    if (result != null) {
      await state.value.upsert(widget.cardId, result.date, result.amount);
      await _load(state);
    }
  }

  void _openHistory(AppState state, TcgCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ValueHistoryScreen(card: card)),
    ).then((_) => _load(state));
  }

  Future<void> _toggleFlag(
    AppState state, {
    bool? forTrade,
    bool? onWishlist,
  }) async {
    final card = _card!;
    final updated = card.copyWith(forTrade: forTrade, onWishlist: onWishlist);
    await state.updateCard(updated);
    setState(() => _card = updated);
  }

  Future<void> _toggleFavorite(AppState state) async {
    final card = _card!;
    final updated = card.copyWith(isFavorite: !card.isFavorite);
    await state.updateCard(updated);
    setState(() => _card = updated);
  }

  Future<void> _moveToFolder(AppState state) async {
    final card = _card!;
    final destination = await pickDestinationFolder(
      context,
      state: state,
      title: 'Move to folder',
      excludeReleaseId: card.releaseId,
    );
    if (destination == null) return;
    await state.moveCards([card.id], releaseId: destination);
    await _load(state);
    _showMoveCopyFeedback('Moved', destination, state);
  }

  Future<void> _copyToFolder(AppState state) async {
    final card = _card!;
    final destination = await pickDestinationFolder(
      context,
      state: state,
      title: 'Copy to folder',
    );
    if (destination == null) return;
    await state.copyCards([card.id], releaseId: destination);
    _showMoveCopyFeedback('Copied', destination, state);
  }

  void _showMoveCopyFeedback(
    String verb,
    String destinationReleaseId,
    AppState state,
  ) {
    if (!mounted) return;
    final name = state.releases
        .firstWhere((r) => r.id == destinationReleaseId)
        .name;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$verb to $name')));
  }

  Release? _release(AppState state, TcgCard card) {
    if (card.releaseId == null) return null;
    for (final r in state.releases) {
      if (r.id == card.releaseId) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder<void>(
      future: _card == null ? _load(state) : null,
      builder: (context, snapshot) {
        final card = _card;
        if (card == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final release = _release(state, card);
        final category = release?.category ?? ReleaseCategory.others;
        final fields = cardMetadataFields(category, card, release);
        final buckets = state.value.buckets(_entries, _range);
        final delta = state.value.deltaVsDaysAgo(_entries, 30);
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(card.isUntitled ? 'Untitled card' : card.name!),
            actions: [
              IconButton(
                tooltip: card.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(card.isFavorite ? Icons.star : Icons.star_border),
                color: card.isFavorite ? scheme.primary : null,
                onPressed: () => _toggleFavorite(state),
              ),
              PopupMenuButton<String>(
                onSelected: (choice) async {
                  switch (choice) {
                    case 'edit':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditCardScreen(card: card),
                        ),
                      );
                      await _load(state);
                      break;
                    case 'trade':
                      await _toggleFlag(state, forTrade: !card.forTrade);
                      break;
                    case 'wishlist':
                      await _toggleFlag(state, onWishlist: !card.onWishlist);
                      break;
                    case 'move':
                      await _moveToFolder(state);
                      break;
                    case 'copy':
                      await _copyToFolder(state);
                      break;
                    case 'delete':
                      final confirmed = await confirmDelete(
                        context,
                        title: 'Delete card?',
                        message: 'This removes the card and its value history.',
                      );
                      if (confirmed) {
                        await state.deleteCard(card.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'trade',
                    child: Text(
                      card.forTrade
                          ? 'Remove from trade list'
                          : 'Mark for trade',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'wishlist',
                    child: Text(
                      card.onWishlist
                          ? 'Remove from wishlist'
                          : 'Add to wishlist',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: Text('Move to folder'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy to folder'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CardImageCarousel(paths: card.photoPaths, copies: card.copies),
              const SizedBox(height: 20),
              CardMetadataGrid(fields: fields),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'VALUE',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add value',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _addValue(state),
                  ),
                  IconButton(
                    tooltip: 'Value history',
                    icon: const Icon(Icons.history),
                    onPressed: () => _openHistory(state, card),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _entries.isEmpty
                        ? '—'
                        : formatCurrency(_entries.last.amount),
                    style: textTheme.displaySmall,
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      delta == null ? '—' : '${formatDelta(delta)} vs 30 days',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<ValueRange>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ValueRange.day, label: Text('D')),
                  ButtonSegment(value: ValueRange.week, label: Text('W')),
                  ButtonSegment(value: ValueRange.month, label: Text('M')),
                  ButtonSegment(value: ValueRange.year, label: Text('Y')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 16),
              ValueGraph(buckets: buckets),
            ],
          ),
        );
      },
    );
  }
}
