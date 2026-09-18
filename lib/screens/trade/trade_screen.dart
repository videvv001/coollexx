import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/tcg_card.dart';
import '../../models/value_entry.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import '../card_detail/card_detail_screen.dart';

enum _TradeTab { forTrade, wishlist }

/// 1d screen 7 — Trade & wishlist. Both lists are driven purely by the two
/// booleans on a card, set from the card detail overflow menu or the
/// folder's bulk "Trade" action.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  _TradeTab _tab = _TradeTab.forTrade;

  Future<void> _export(
    AppState state,
    List<TcgCard> cards,
    Map<String, ValueEntry> latest,
  ) async {
    final buffer = StringBuffer('Name,Number,Copies,Value\n');
    for (final card in cards) {
      final value = latest[card.id]?.amount;
      buffer.writeln(
        [
          card.name ?? 'Untitled',
          card.number ?? '',
          card.copies,
          value?.toStringAsFixed(2) ?? '',
        ].join(','),
      );
    }
    await Share.share(buffer.toString(), subject: 'Trade list');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return FutureBuilder(
      future: Future.wait([
        state.collection.search(),
        state.value.latestPerCard(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final allCards = snapshot.data![0] as List<TcgCard>;
        final latest = snapshot.data![1] as Map<String, ValueEntry>;
        final forTrade = allCards.where((c) => c.forTrade).toList();
        final wishlist = allCards.where((c) => c.onWishlist).toList();
        final shown = _tab == _TradeTab.forTrade ? forTrade : wishlist;

        double listValue = 0;
        for (final c in forTrade) {
          final v = latest[c.id]?.amount;
          if (v != null) listValue += v * c.copies;
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Trade')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<_TradeTab>(
                  segments: [
                    ButtonSegment(
                      value: _TradeTab.forTrade,
                      label: Text('For trade ${forTrade.length}'),
                    ),
                    ButtonSegment(
                      value: _TradeTab.wishlist,
                      label: Text('Wishlist ${wishlist.length}'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          _tab == _TradeTab.forTrade
                              ? 'No cards marked for trade'
                              : 'No cards on your wishlist',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final card = shown[index];
                          final value = latest[card.id]?.amount;
                          return ListTile(
                            leading: SizedBox(
                              width: 40,
                              child: PhotoPlaceholder(
                                path: card.thumbnailPath,
                                dashed: !card.hasPhoto,
                              ),
                            ),
                            title: Text(
                              card.isUntitled ? 'Untitled' : card.name!,
                            ),
                            subtitle: Text(
                              [
                                if (card.number != null) '#${card.number}',
                                'have ${card.copies}',
                              ].join(' · '),
                            ),
                            trailing: Text(
                              value != null
                                  ? '\$${value.toStringAsFixed(2)}'
                                  : '—',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CardDetailScreen(cardId: card.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_tab == _TradeTab.forTrade)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'List value \$${listValue.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _export(state, forTrade, latest),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Export CSV'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
