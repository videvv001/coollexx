import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/card_condition.dart';
import '../../models/sub_folder.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
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
  String? _subFolderId;
  List<SubFolder> _subFolders = [];
  CardCondition? _condition;
  int _copies = 1;
  DateTime? _datePaid;
  bool _forTrade = false;
  bool _onWishlist = false;

  @override
  void initState() {
    super.initState();
    _releaseId = widget.boundReleaseId;
    if (_releaseId != null) _loadSubFolders();
  }

  Future<void> _loadSubFolders() {
    final state = context.read<AppState>();
    return state.collection.subFoldersFor(_releaseId!).then((v) {
      if (mounted) setState(() => _subFolders = v);
    });
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

  Future<TcgCard> _buildAndSave(AppState state) async {
    final card = TcgCard(
      id: _uuid.v4(),
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      number: _numberController.text.trim().isEmpty
          ? null
          : _numberController.text.trim(),
      condition: _condition,
      copies: _copies,
      releaseId: _releaseId,
      subFolderId: _subFolderId,
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
    Navigator.of(context).popUntil(ModalRoute.withName(captureRouteName));
    Navigator.of(context).pop();
  }

  Future<void> _saveAndNew(AppState state) async {
    await _buildAndSave(state);
    if (!mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName(captureRouteName));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Name, tag & file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
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
            onChanged: (v) {
              setState(() {
                _releaseId = v;
                _subFolderId = null;
                _subFolders = [];
              });
              if (v != null) _loadSubFolders();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _numberController,
            decoration: const InputDecoration(labelText: 'Number'),
          ),
          if (_releaseId != null) ...[
            const SizedBox(height: 12),
            Text(
              'Sub-folder — optional, default "None"',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _subFolderId == null,
                  onSelected: (_) => setState(() => _subFolderId = null),
                ),
                for (final sf in _subFolders)
                  ChoiceChip(
                    label: Text(sf.name),
                    selected: _subFolderId == sf.id,
                    onSelected: (_) => setState(() => _subFolderId = sf.id),
                  ),
              ],
            ),
          ],
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
