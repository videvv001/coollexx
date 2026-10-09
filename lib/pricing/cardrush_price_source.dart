import 'dart:convert';

import 'japanese_price_source.dart';
import 'price_research_service.dart';

/// CardRush (カードラッシュ), read through its own keyword search: one plain
/// HTTP GET of server-rendered HTML, no AI. It sells each printing — and each
/// condition grade, and graded copies — as its own product, titled like
/// `〔状態B〕モンキー・D・ルフィ(パラレル/illust:Minato Sashima)【SEC/P】{ EB04-061 }`.
///
/// A listing is this printing only when its number and rarity agree and its
/// `(…)` label is one of the labels verified for our printing in
/// [_signatures] — never because the number matches. Prices are asking
/// prices ([SourceType.currentListing]) in yen. Graded and condition-grade
/// listings are kept as evidence but never priced.
class CardRushPriceSource implements JapanesePriceSource {
  CardRushPriceSource({
    Future<String> Function(Uri url)? fetch,
    DateTime Function()? clock,
  }) : _fetch = fetch ?? fetchPage,
       _clock = clock ?? DateTime.now;

  final Future<String> Function(Uri url) _fetch;
  final DateTime Function() _clock;

  @override
  String get marketplace => 'CardRush';

  @override
  Future<SourceResult> research(PrintingDescriptor printing) async {
    final number = printing.cardNumber.trim().toUpperCase();
    final key = printing.variant.name ?? printing.variant.family.code;
    final label = printing.variant.displayLabel;
    final matches = _signatures[key];
    if (matches == null) {
      return SourceResult(
        marketplace: marketplace,
        status: SourceStatus.insufficientEvidence,
        reason:
            'No verified CardRush label for "$label" yet, so its listings of '
            '$number can\'t be matched to it.',
      );
    }
    // ponytail: one page of up to 60 products. A number with more than that
    // (cards sold in every condition and grade) needs `&page=2`; none of ours
    // does yet.
    final url = Uri.https('www.cardrush-op.jp', '/product-list', {
      'keyword': number,
      'num': '60',
    });
    final String html;
    try {
      html = await _fetch(url);
    } catch (e) {
      return SourceResult.failed(marketplace, 'CardRush request failed: $e');
    }
    final entries = parseCardRushList(
      html,
    ).where((e) => e.number == number).toList();
    final raw = jsonEncode([for (final e in entries) e.toJson()]);
    final now = _clock();

    final wantedRarity = printing.rarity?.trim().toUpperCase().replaceFirst(
      RegExp(r'^P-'),
      '',
    );
    bool isExact(CardRushEntry e) =>
        matches(e) && (wantedRarity == null || e.baseRarity == wantedRarity);

    String? excluded(CardRushEntry e) {
      if (e.isGraded) return 'graded copy (${e.prefixes.join(' ')})';
      if (e.prefixes.isNotEmpty) {
        return 'not a new copy (${e.prefixes.join(' ')})';
      }
      return null;
    }

    return resolveCandidates(
      marketplace: marketplace,
      printingLabel: label,
      number: number,
      raw: raw,
      candidates: [
        for (final e in entries)
          Candidate(
            exact: isExact(e),
            excludedReason: excluded(e),
            soldOut: !e.inStock,
            observations: [
              PriceSource(
                name: 'CardRush',
                marketplace: 'CardRush',
                type: SourceType.currentListing,
                price: e.price.toDouble(),
                currency: 'JPY',
                isGraded: e.isGraded,
                condition: e.prefixes.isEmpty ? null : e.prefixes.join(' '),
                url: e.url,
                title: '${e.title}${e.inStock ? '' : ' (sold out)'}',
                sourceLabel: e.title,
                matchConfidence: isExact(e) ? 1.0 : null,
                soldOut: !e.inStock,
                observedAt: now,
                usedInEstimate: false,
              ),
            ],
          ),
      ],
    );
  }
}

/// Our printing → "is this CardRush listing that printing?", by its `(…)`
/// labels. Keyed by the variant's name, or its family code when it has none.
/// Verified against real listings (2026-10-05): the regular print has no
/// label and a plain `SEC`; a parallel is `(パラレル/illust:<artist>)` with
/// rarity `SEC/P`; EB04-061's crew-background print is `(海賊団背景)`. A
/// printing without an entry is never priced from CardRush.
final _signatures = <String, bool Function(CardRushEntry)>{
  'BASE': (e) => e.groups.isEmpty && !e.rarity.contains('/'),
  'PARALLEL': (e) =>
      e.groups.length == 1 && e.groups.single.split('/').first == 'パラレル',
  'PIRATE_CREW_SUPER_PARALLEL': (e) =>
      e.groups.length == 1 && e.groups.single == '海賊団背景',
};

class CardRushEntry {
  const CardRushEntry({
    required this.title,
    required this.number,
    required this.rarity,
    required this.price,
    required this.inStock,
    required this.url,
    this.setTag,
    this.prefixes = const [],
    this.groups = const [],
  });

  /// The product title exactly as CardRush shows it.
  final String title;
  final String number;

  /// `SEC`, or `SEC/P` for a parallel.
  final String rarity;
  final String? setTag;

  /// Leading `〔…〕` tags: condition grade (`状態B`), grading (`PSA10鑑定済`).
  final List<String> prefixes;

  /// Every `(…)` label on the card name, in order.
  final List<String> groups;
  final int price;
  final bool inStock;
  final String url;

  bool get isGraded => prefixes.any((p) => p.contains('鑑定'));

  /// Rarity without the `/P` flag or a `P-` prefix.
  String get baseRarity =>
      rarity.split('/').first.toUpperCase().replaceFirst(RegExp(r'^P-'), '');

  Map<String, Object?> toJson() => {
    'title': title,
    'number': number,
    'rarity': rarity,
    'set': setTag,
    'prefixes': prefixes,
    'labels': groups,
    'price_jpy': price,
    'in_stock': inStock,
    'url': url,
  };
}

/// Every priced product on a CardRush search page.
List<CardRushEntry> parseCardRushList(String html) {
  final entries = <CardRushEntry>[];
  for (final cell in html.split('<li class="list_item_cell').skip(1)) {
    // The name's own </span> is followed by the model-number span; the search
    // keyword inside the name is wrapped in a <span><b> of its own.
    final title = RegExp(
      r'class="goods_name">(.*?)</span>\s*(?:<wbr\s*/?>\s*)?<span class="model_number"',
      dotAll: true,
    ).firstMatch(cell)?.group(1);
    final price = RegExp(r'class="figure">\s*([\d,]+)\s*円').firstMatch(cell);
    final link = RegExp(
      r'href="(https://www\.cardrush-op\.jp/product/\d+)"',
    ).firstMatch(cell);
    if (title == null || price == null || link == null) continue;
    final text = _unescape(title.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
    final number = RegExp(
      r'\{\s*([A-Za-z0-9]+-\d+)\s*(?:\[([^\]]*)\])?\s*\}',
    ).firstMatch(text);
    final rarity = RegExp(r'【([^】]+)】').firstMatch(text);
    if (number == null || rarity == null) continue;
    final name = text.substring(0, rarity.start);
    final stock = RegExp(r'class="stock">([^<]*)<').firstMatch(cell)?.group(1);
    entries.add(
      CardRushEntry(
        title: text,
        number: number.group(1)!.toUpperCase(),
        setTag: number.group(2)?.trim(),
        rarity: rarity.group(1)!.trim(),
        prefixes: [
          for (final m in RegExp(r'〔([^〕]+)〕').allMatches(name))
            m.group(1)!.trim(),
        ],
        groups: [
          for (final m in RegExp(r'[(（]([^)）]*)[)）]').allMatches(name))
            m.group(1)!.trim(),
        ],
        price: int.parse(price.group(1)!.replaceAll(',', '')),
        inStock: stock != null && !stock.contains('在庫なし'),
        url: link.group(1)!,
      ),
    );
  }
  return entries;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&#39;', "'");
