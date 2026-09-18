import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/photo_store.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../shared/card_category_fields.dart';
import '../shared/card_image_viewer.dart';
import '../shared/photo_editor_screen.dart';
import '../shared/photo_source_sheet.dart';

/// Edits every field on a card, including its photo gallery: add photos
/// (camera/gallery, run through `PhotoEditorScreen`), remove them, and pick
/// which one is the thumbnail (`TcgCard.photoPaths.first`). Mirrors
/// `NameTagFileScreen`'s field set/widgets so the two forms feel the same.
class EditCardScreen extends StatefulWidget {
  const EditCardScreen({super.key, required this.card});

  final TcgCard card;

  @override
  State<EditCardScreen> createState() => _EditCardScreenState();
}

class _EditCardScreenState extends State<EditCardScreen> {
  late final _nameController = TextEditingController(text: widget.card.name);
  late final _numberController = TextEditingController(
    text: widget.card.number,
  );
  late final _paidController = TextEditingController(
    text: widget.card.pricePaid?.toString(),
  );
  late final _notesController = TextEditingController(text: widget.card.notes);

  late String? _releaseId = widget.card.releaseId;
  late CardLanguage? _language = widget.card.language;
  late String? _rarity = widget.card.rarity;
  late String? _kind = widget.card.kind;
  late String? _color = widget.card.color;
  late String? _type = widget.card.type;
  late CardCondition? _condition = widget.card.condition;
  late int _copies = widget.card.copies;
  late DateTime? _datePaid = widget.card.datePaid;
  late bool _forTrade = widget.card.forTrade;
  late bool _onWishlist = widget.card.onWishlist;
  final List<String> _photoPaths = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _photoPaths.addAll(widget.card.photoPaths);
  }

  ReleaseCategory _category(AppState state) {
    if (_releaseId == null) return ReleaseCategory.others;
    for (final r in state.releases) {
      if (r.id == _releaseId) return r.category;
    }
    return ReleaseCategory.others;
  }

  Future<void> _pickDatePaid() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datePaid ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _datePaid = picked);
  }

  Future<void> _addPhoto() async {
    final sourcePath = await pickPhotoSource(context);
    if (sourcePath == null || !mounted) return;
    final savedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PhotoEditorScreen(sourcePath: sourcePath, aspectRatio: 5 / 7),
      ),
    );
    if (savedPath == null) return;
    setState(() => _photoPaths.add(savedPath));
  }

  void _setThumbnail(int index) {
    setState(() {
      final path = _photoPaths.removeAt(index);
      _photoPaths.insert(0, path);
    });
  }

  Future<void> _removePhoto(int index) async {
    final path = _photoPaths[index];
    setState(() => _photoPaths.removeAt(index));
    await PhotoStore.instance.delete(path);
  }

  Future<void> _save(AppState state) async {
    setState(() => _saving = true);
    final updated = TcgCard(
      id: widget.card.id,
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
      condition: _condition,
      copies: _copies,
      releaseId: _releaseId,
      photoPaths: _photoPaths,
      pricePaid: double.tryParse(_paidController.text.trim()),
      datePaid: _datePaid,
      forTrade: _forTrade,
      onWishlist: _onWishlist,
      isFavorite: widget.card.isFavorite,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: widget.card.createdAt,
    );
    await state.updateCard(updated);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final category = _category(state);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit card'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(state),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Card details', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _releaseId,
            decoration: const InputDecoration(labelText: 'Release'),
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
          const SizedBox(height: 12),
          CardCategoryFields(
            category: category,
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
          const SizedBox(height: 20),
          Text(
            'Collection details',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text('Condition', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<CardCondition?>(
            segments: const [
              ButtonSegment(value: null, label: Text('—')),
              ButtonSegment(value: CardCondition.nm, label: Text('NM')),
              ButtonSegment(value: CardCondition.ex, label: Text('EX')),
              ButtonSegment(value: CardCondition.gd, label: Text('GD')),
              ButtonSegment(value: CardCondition.pl, label: Text('PL')),
            ],
            selected: {_condition},
            onSelectionChanged: (s) => setState(() => _condition = s.first),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _paidController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Paid',
                    prefixText: '\$ ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _pickDatePaid,
                child: Text(
                  _datePaid == null
                      ? 'Date paid'
                      : '${_datePaid!.day}/${_datePaid!.month}/${_datePaid!.year}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
            minLines: 2,
            maxLines: 4,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mark for trade'),
            value: _forTrade,
            onChanged: (v) => setState(() => _forTrade = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('On wishlist'),
            value: _onWishlist,
            onChanged: (v) => setState(() => _onWishlist = v),
          ),
          const SizedBox(height: 20),
          Text('Photos', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoPaths.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == _photoPaths.length) {
                  return GestureDetector(
                    onTap: _addPhoto,
                    child: SizedBox(
                      width: 80,
                      child: PhotoPlaceholder(
                        dashed: true,
                        icon: Icons.add,
                        borderRadius: 10,
                      ),
                    ),
                  );
                }
                final isThumbnail = index == 0;
                return SizedBox(
                  width: 80,
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () => openCardImageViewer(
                          context,
                          _photoPaths,
                          initialIndex: index,
                        ),
                        child: PhotoPlaceholder(
                          path: _photoPaths[index],
                          borderRadius: 10,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: GestureDetector(
                          onTap: () => _setThumbnail(index),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: isThumbnail
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black45,
                            child: Icon(
                              isThumbnail ? Icons.star : Icons.star_border,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removePhoto(index),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black45,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
