import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/card_language.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../shared/card_category_fields.dart';

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
  final _numberController = TextEditingController();
  String? _releaseId;
  CardLanguage? _language;
  String? _rarity;
  String? _kind;
  String? _color;
  String? _type;
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    _releaseId = widget.releaseId;
  }

  ReleaseCategory _category(AppState state) {
    if (_releaseId == null) return ReleaseCategory.others;
    for (final r in state.releases) {
      if (r.id == _releaseId) return r.category;
    }
    return ReleaseCategory.others;
  }

  Future<void> _save(AppState state) async {
    final card = TcgCard(
      id: _uuid.v4(),
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      number: _numberController.text.trim().isEmpty
          ? null
          : _numberController.text.trim(),
      rarity: _rarity,
      language: _language,
      kind: _kind,
      color: _color,
      type: _type,
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
          CardCategoryFields(
            category: _category(state),
            idController: _numberController,
            nameController: _nameController,
            language: _language,
            onLanguageChanged: (v) => setState(() => _language = v),
            rarity: _rarity,
            onRarityChanged: (v) => setState(() => _rarity = v),
            kind: _kind,
            onKindChanged: (v) => setState(() => _kind = v),
            color: _color,
            onColorChanged: (v) => setState(() => _color = v),
            type: _type,
            onTypeChanged: (v) => setState(() => _type = v),
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
