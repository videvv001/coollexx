import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/value_repository.dart';
import '../../models/card_condition.dart';
import '../../models/tcg_card.dart';
import '../../models/value_entry.dart';
import '../../state/app_state.dart';
import '../../utils/formatting.dart';
import '../../widgets/photo_placeholder.dart';
import 'add_value_sheet.dart';
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

  Future<void> _setCopies(AppState state, int delta) async {
    final card = _card!;
    final copies = (card.copies + delta).clamp(1, 9999);
    final updated = card.copyWith(copies: copies);
    await state.updateCard(updated);
    setState(() => _card = updated);
  }

  Future<void> _setCondition(AppState state, CardCondition? condition) async {
    final card = _card!;
    final updated = card.copyWith(
      condition: condition,
      clearCondition: condition == null,
    );
    await state.updateCard(updated);
    setState(() => _card = updated);
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
        final windowed = state.value.windowed(_entries, _range);
        final delta = state.value.deltaVsDaysAgo(_entries, 30);
        return Scaffold(
          appBar: AppBar(
            title: Text(card.isUntitled ? 'Untitled card' : card.name!),
            actions: [
              PopupMenuButton<String>(
                onSelected: (choice) async {
                  switch (choice) {
                    case 'trade':
                      await _toggleFlag(state, forTrade: !card.forTrade);
                      break;
                    case 'wishlist':
                      await _toggleFlag(state, onWishlist: !card.onWishlist);
                      break;
                    case 'delete':
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete card?'),
                          content: const Text(
                            'This removes the card and its value history.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await state.deleteCard(card.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
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
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: PhotoPlaceholder(
                      path: card.thumbnailPath,
                      dashed: !card.hasPhoto,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (card.number != null) Text('#${card.number}'),
                        if (card.rarity != null) Text(card.rarity!),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Copies'),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _setCopies(state, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${card.copies}'),
                            IconButton(
                              onPressed: () => _setCopies(state, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final c in CardCondition.values)
                              ChoiceChip(
                                label: Text(c.label),
                                selected: card.condition == c,
                                onSelected: (selected) =>
                                    _setCondition(state, selected ? c : null),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'My value · latest',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _entries.isEmpty
                        ? '—'
                        : '\$${_entries.last.amount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      delta == null ? '—' : '${formatDelta(delta)} vs 30 days',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<ValueRange>(
                segments: const [
                  ButtonSegment(value: ValueRange.day, label: Text('Day')),
                  ButtonSegment(value: ValueRange.week, label: Text('Week')),
                  ButtonSegment(value: ValueRange.month, label: Text('Month')),
                  ButtonSegment(value: ValueRange.year, label: Text('Year')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 16),
              ValueGraph(entries: windowed),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _entries.isEmpty
                          ? 'No entries yet'
                          : 'Last entry ${formatShortDate(_entries.last.date)} · ${_entries.length} entries',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ValueHistoryScreen(card: card),
                      ),
                    ).then((_) => _load(state)),
                    child: const Text('History'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _addValue(state),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a value'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
