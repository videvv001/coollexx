import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/card_text_scan.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../state/ocr_settings.dart';
import '../shared/card_category_fields.dart';
import '../shared/category_prompt.dart';
import 'capture_route.dart';

/// 1c step 3 — Name, tag, file. The end of the guided-scan path: unlike
/// burst, each card is fully tagged before the next shot.
class NameTagFileScreen extends StatefulWidget {
  const NameTagFileScreen({
    super.key,
    required this.photoPaths,
    this.boundReleaseId,
    this.boundSetSlotNumber,
  });

  final List<String> photoPaths;
  final String? boundReleaseId;
  final String? boundSetSlotNumber;

  @override
  State<NameTagFileScreen> createState() => _NameTagFileScreenState();
}

class _NameTagFileScreenState extends State<NameTagFileScreen> {
  static const _uuid = Uuid();
  final _nameController = TextEditingController();
  late final _numberController = TextEditingController(
    text: widget.boundSetSlotNumber ?? '',
  );
  final _paidController = TextEditingController();
  String? _releaseId;
  CardLanguage? _language;
  String? _rarity;
  String? _kind;
  String? _color;
  String? _type;
  CardCondition? _condition;
  int _copies = 1;
  DateTime? _datePaid;
  bool _forTrade = false;
  bool _onWishlist = false;
  bool _scanning = false;
  // Set from the category prompt when no bound release already answers the
  // question — also used by `_category` below, so once picked it drives
  // which fields CardCategoryFields shows too, not just the OCR heuristic.
  ReleaseCategory? _ocrCategoryOverride;

  @override
  void initState() {
    super.initState();
    _releaseId = widget.boundReleaseId;
    // Deferred a frame so the prompt dialog (if needed) has a built screen
    // to anchor to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runOcr());
  }

  /// Prefills name/number/kind/language from on-device text recognition of
  /// the front photo (see `scanCardText`) — purely a suggestion: it never
  /// overwrites a field the user already touched while the scan was
  /// running. Skipped entirely if OCR is turned off, or if the card turns
  /// out to be a category this app doesn't know the layout of.
  Future<void> _runOcr() async {
    if (widget.photoPaths.isEmpty) return;
    final settings = context.read<OcrSettings>();
    if (!settings.enabled) return;
    final state = context.read<AppState>();

    var category = _knownCategory(state);
    if (category == null) {
      if (!mounted) return;
      category = await pickOcrCategory(context) ?? ReleaseCategory.others;
      if (!mounted) return;
      setState(() => _ocrCategoryOverride = category);
    }
    if (category == ReleaseCategory.others) return;

    setState(() => _scanning = true);
    final guess = await scanCardText(widget.photoPaths.first, category);
    if (!mounted) return;
    setState(() {
      _scanning = false;
      if (_nameController.text.trim().isEmpty && guess.name != null) {
        _nameController.text = guess.name!;
      }
      if (_numberController.text.trim().isEmpty && guess.number != null) {
        _numberController.text = guess.number!;
      }
      if (_kind == null && guess.kind != null) {
        _kind = guess.kind;
      }
      if (_language == null && guess.language != null) {
        _language = guess.language;
      }
    });
  }

  /// The category a bound release *confidently* tells us — null means
  /// "ask" (see `_runOcr`). Only Pokémon/One Piece count: `others` is also
  /// what a release gets when nobody ever picked a category (it's the
  /// silent default at creation and the fallback for a missing value), so
  /// treating it as an answer would mean never scanning, and never asking
  /// either. `_category` below is the version the rest of the form uses,
  /// which falls back to the prompt's answer.
  ReleaseCategory? _knownCategory(AppState state) {
    if (_releaseId == null) return null;
    for (final r in state.releases) {
      if (r.id == _releaseId) {
        return r.category == ReleaseCategory.others ? null : r.category;
      }
    }
    return null;
  }

  ReleaseCategory _category(AppState state) =>
      _knownCategory(state) ?? _ocrCategoryOverride ?? ReleaseCategory.others;

  Future<void> _pickDatePaid() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _datePaid ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _datePaid = picked);
  }

  Future<TcgCard> _buildAndSave(AppState state) async {
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
      condition: _condition,
      copies: _copies,
      releaseId: _releaseId,
      photoPaths: widget.photoPaths,
      pricePaid: double.tryParse(_paidController.text.trim()),
      datePaid: _datePaid,
      forTrade: _forTrade,
      onWishlist: _onWishlist,
      createdAt: DateTime.now(),
    );
    return state.addCard(card);
  }

  Future<void> _save(AppState state) async {
    await _buildAndSave(state);
    if (!mounted) return;
    popCaptureFlow(context, exit: true);
  }

  Future<void> _saveAndNew(AppState state) async {
    await _buildAndSave(state);
    if (!mounted) return;
    // Reached straight from a folder's gallery upload there's no camera
    // behind this screen to go back to for a "new" card, so leave instead
    // of sitting on a filled-in form that would save the same photo twice.
    final atEntry = ModalRoute.of(context)?.settings.name == captureRouteName;
    popCaptureFlow(context, exit: atEntry);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Name, tag & file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Scanning card…'),
                ],
              ),
            ),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _saveAndNew(state),
                  child: const Text('Save & new'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _save(state),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
