import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/tcg_card.dart';
import '../../state/app_state.dart';

/// 1d screen 6 — "Add without a photo". No local card catalogue is bundled
/// (auto-match needs a server and was cut), so this always goes straight to
/// custom entry.
class AddManualScreen extends StatefulWidget {
  const AddManualScreen({super.key, this.releaseId});

  final String? releaseId;

  @override
  State<AddManualScreen> createState() => _AddManualScreenState();
}

class _AddManualScreenState extends State<AddManualScreen> {
  static const _uuid = Uuid();
  final _nameController = TextEditingController();
  String? _releaseId;
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    _releaseId = widget.releaseId;
  }

  Future<void> _save(AppState state) async {
    final card = TcgCard(
      id: _uuid.v4(),
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      copies: _copies,
      releaseId: _releaseId,
      createdAt: DateTime.now(),
    );
    await state.addCard(card);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Add without a photo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _releaseId,
            decoration: const InputDecoration(labelText: 'Release folder'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('None — unsorted'),
              ),
              for (final r in state.releases)
                DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => _releaseId = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Copies'),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    setState(() => _copies = (_copies - 1).clamp(1, 9999)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_copies'),
              IconButton(
                onPressed: () => setState(() => _copies++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No photo yet — the card shows as a dashed slot until you scan it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _save(state),
              child: const Text('Add to collection'),
            ),
          ),
        ],
      ),
    );
  }
}
