import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tcg_card.dart';
import '../../models/value_entry.dart';
import '../../state/app_state.dart';
import '../../utils/formatting.dart';
import 'add_value_sheet.dart';

class ValueHistoryScreen extends StatefulWidget {
  const ValueHistoryScreen({super.key, required this.card});

  final TcgCard card;

  @override
  State<ValueHistoryScreen> createState() => _ValueHistoryScreenState();
}

class _ValueHistoryScreenState extends State<ValueHistoryScreen> {
  bool _editing = false;
  List<ValueEntry> _entries = [];

  Future<void> _load(AppState state) async {
    final entries = await state.value.allForCard(widget.card.id);
    entries.sort((a, b) => b.date.compareTo(a.date)); // newest first
    setState(() => _entries = entries);
  }

  Future<void> _addValue(AppState state) async {
    final result = await showModalBottomSheet<({DateTime date, double amount})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddValueSheet(
        lastAmount: _entries.isEmpty ? null : _entries.first.amount,
      ),
    );
    if (result != null) {
      await state.value.upsert(widget.card.id, result.date, result.amount);
      await _load(state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder<void>(
      future: _entries.isEmpty ? _load(state) : null,
      builder: (context, snapshot) {
        final gain = widget.card.pricePaid != null && _entries.isNotEmpty
            ? _entries.first.amount - widget.card.pricePaid!
            : null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Value history'),
            actions: [
              TextButton(
                onPressed: () => setState(() => _editing = !_editing),
                child: Text(_editing ? 'Done' : 'Edit'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.card.pricePaid != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.card.datePaid != null
                                    ? '${formatLongDate(widget.card.datePaid!)} · bought · '
                                          '\$${widget.card.pricePaid!.toStringAsFixed(2)}'
                                    : 'Bought · \$${widget.card.pricePaid!.toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              for (final entry in _entries)
                _EntryRow(
                  entry: entry,
                  previous: _previousOf(entry),
                  editing: _editing,
                  onDelete: () async {
                    await state.value.delete(entry.id);
                    await _load(state);
                  },
                  onEdit: () async {
                    final result =
                        await showModalBottomSheet<
                          ({DateTime date, double amount})
                        >(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => AddValueSheet(editing: entry),
                        );
                    if (result != null) {
                      await state.value.upsert(
                        widget.card.id,
                        result.date,
                        result.amount,
                      );
                      await _load(state);
                    }
                  },
                ),
              if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No value recorded',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (gain != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Gain since bought ${formatDelta(gain)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
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

  ValueEntry? _previousOf(ValueEntry entry) {
    final idx = _entries.indexOf(entry);
    if (idx == -1 || idx == _entries.length - 1) return null;
    return _entries[idx + 1];
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.previous,
    required this.editing,
    required this.onDelete,
    required this.onEdit,
  });

  final ValueEntry entry;
  final ValueEntry? previous;
  final bool editing;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : entry.amount - previous!.amount;
    final row = ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(formatLongDate(entry.date)),
      subtitle: delta != null ? Text(formatDelta(delta)) : null,
      trailing: Text(
        '\$${entry.amount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: editing ? onEdit : null,
    );
    if (!editing) return row;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDelete(),
      child: row,
    );
  }
}
