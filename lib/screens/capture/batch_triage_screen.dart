import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import 'assign_release_screen.dart';

/// 1a step 2 — Batch triage. Also doubles as the "sort the unsorted tray"
/// screen: without auto-match every shot lands here nameless either way, so
/// a fresh burst session and a return visit to old unsorted photos are the
/// same screen over the same underlying "no release yet" cards.
class BatchTriageScreen extends StatefulWidget {
  const BatchTriageScreen({
    super.key,
    required this.shotPaths,
    this.boundReleaseId,
    this.useUnsortedTray = false,
  });

  final List<String> shotPaths;
  final String? boundReleaseId;
  final bool useUnsortedTray;

  @override
  State<BatchTriageScreen> createState() => _BatchTriageScreenState();
}

class _BatchTriageScreenState extends State<BatchTriageScreen> {
  static const _uuid = Uuid();
  List<TcgCard> _cards = [];
  bool _loading = true;

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
      final created = <TcgCard>[];
      for (final path in widget.shotPaths) {
        final card = await state.addCard(
          TcgCard(
            id: _uuid.v4(),
            photoPaths: [path],
            createdAt: DateTime.now(),
          ),
        );
        created.add(card);
      }
      _cards = created;
    }
    if (!mounted) return;
    setState(() => _loading = false);
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
    ScaffoldMessenger.of(context).showSnackBar(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bin all?'),
        content: Text('Deletes all ${_cards.length} shots in this batch.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bin all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = List.of(_cards);
    await state.deleteCards(removed.map((c) => c.id).toList());
    setState(() => _cards.clear());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
                  leading: SizedBox(
                    width: 44,
                    child: PhotoPlaceholder(
                      path: card.thumbnailPath,
                      dashed: !card.hasPhoto,
                    ),
                  ),
                  title: Text(
                    card.isUntitled ? 'untitled — tap to name' : card.name!,
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
