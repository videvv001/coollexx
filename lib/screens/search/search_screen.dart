import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/card_condition.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../card_detail/card_detail_screen.dart';

class SearchFilters {
  String? releaseId;
  String? subFolderId;
  CardCondition? condition;
  bool onlyPhotographed = false;
  final Set<String> rarities = {};

  bool get isEmpty =>
      releaseId == null &&
      subFolderId == null &&
      condition == null &&
      !onlyPhotographed &&
      rarities.isEmpty;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.openFilter = false});

  final bool openFilter;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  final _filters = SearchFilters();
  List<TcgCard> _results = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _search();
    if (widget.openFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openFilterSheet());
    }
  }

  Future<void> _search() async {
    final state = context.read<AppState>();
    final results = await state.collection.search(
      query: _queryController.text,
      releaseId: _filters.releaseId,
      subFolderId: _filters.subFolderId,
      conditionLabel: _filters.condition?.label,
      onlyPhotographed: _filters.onlyPhotographed,
      rarities: _filters.rarities.isEmpty ? null : _filters.rarities.toList(),
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loaded = true;
    });
  }

  Future<void> _openFilterSheet() async {
    final state = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _FilterSheet(filters: _filters, state: state, onApply: _search),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          autofocus: !widget.openFilter,
          decoration: const InputDecoration(
            hintText: 'Search your collection',
            border: InputBorder.none,
          ),
          onChanged: (_) => _search(),
        ),
        actions: [
          IconButton(
            icon: Icon(_filters.isEmpty ? Icons.tune : Icons.filter_alt),
            onPressed: _openFilterSheet,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
              child: Text(
                'No cards match',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 5 / 7,
              ),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final card = _results[index];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CardDetailScreen(cardId: card.id),
                    ),
                  ),
                  child: PhotoPlaceholder(
                    path: card.thumbnailPath,
                    dashed: !card.hasPhoto,
                    borderRadius: 6,
                  ),
                );
              },
            ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.filters,
    required this.state,
    required this.onApply,
  });

  final SearchFilters filters;
  final AppState state;
  final VoidCallback onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _recount();
  }

  Future<void> _recount() async {
    final results = await widget.state.collection.search(
      releaseId: widget.filters.releaseId,
      subFolderId: widget.filters.subFolderId,
      conditionLabel: widget.filters.condition?.label,
      onlyPhotographed: widget.filters.onlyPhotographed,
      rarities: widget.filters.rarities.isEmpty
          ? null
          : widget.filters.rarities.toList(),
    );
    if (!mounted) return;
    setState(() => _count = results.length);
  }

  static const _rarityOptions = [
    'Common',
    'Uncommon',
    'Rare',
    'Holo Rare',
    'Ultra Rare',
  ];

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  f.releaseId = null;
                  f.subFolderId = null;
                  f.condition = null;
                  f.onlyPhotographed = false;
                  f.rarities.clear();
                  _recount();
                }),
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Rarity', style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final r in _rarityOptions)
                FilterChip(
                  label: Text(r),
                  selected: f.rarities.contains(r),
                  onSelected: (selected) {
                    setState(() {
                      selected ? f.rarities.add(r) : f.rarities.remove(r);
                    });
                    _recount();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Release', style: Theme.of(context).textTheme.labelLarge),
          DropdownButtonFormField<String?>(
            initialValue: f.releaseId,
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              for (final r in widget.state.releases)
                DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (v) {
              setState(() => f.releaseId = v);
              _recount();
            },
          ),
          const SizedBox(height: 12),
          Text('Condition', style: Theme.of(context).textTheme.labelLarge),
          SegmentedButton<CardCondition?>(
            segments: const [
              ButtonSegment(value: null, label: Text('Any')),
              ButtonSegment(value: CardCondition.nm, label: Text('NM')),
              ButtonSegment(value: CardCondition.ex, label: Text('EX')),
              ButtonSegment(value: CardCondition.gd, label: Text('GD+')),
            ],
            selected: {f.condition},
            onSelectionChanged: (s) {
              setState(() => f.condition = s.first);
              _recount();
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Only cards I've photographed"),
            value: f.onlyPhotographed,
            onChanged: (v) {
              setState(() => f.onlyPhotographed = v);
              _recount();
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onApply();
                Navigator.pop(context);
              },
              child: Text('Show $_count results'),
            ),
          ),
        ],
      ),
    );
  }
}
