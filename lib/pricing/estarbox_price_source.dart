import 'dart:convert';

import 'japanese_price_source.dart';
import 'price_research_service.dart';

/// e-Starbox (eスターボックス, tcgkakaku.e-starbox.com): a price-COMPARISON
/// site, not a shop. It shows what shops ask for each card, so its numbers are
/// [SourceType.priceComparison], and its 買取 (buyback) table is never read.
///
/// Its search is unusable for card numbers (always "0件"), but every print has
/// its own page whose id is the number plus the rarity and a running index:
/// `OPEB04/061SEC`, `…SEC1`, `…SEC2`, `…SEC3`. Those pages are probed in order
/// until the first 404, and each is judged against the requested printing by
/// the rarity line it shows (`シークレットレア / 海賊団パラレル`) — the number
/// and the rarity alone say nothing about which print a page is.
class EStarboxPriceSource implements JapanesePriceSource {
  EStarboxPriceSource({
    Future<String> Function(Uri url)? fetch,
    DateTime Function()? clock,
    this.maxPrints = 8,
  }) : _fetch = fetch ?? fetchPage,
       _clock = clock ?? DateTime.now;

  final Future<String> Function(Uri url) _fetch;
  final DateTime Function() _clock;

  /// How many pages (prints of one number + rarity) to probe at most.
  final int maxPrints;

  @override
  String get marketplace => 'e-Starbox';

  @override
  Future<SourceResult> research(PrintingDescriptor printing) async {
    final number = printing.cardNumber.trim().toUpperCase();
    final key = printing.variant.name ?? printing.variant.family.code;
    final label = printing.variant.displayLabel;
    final tags = _printTags[key];
    final parts = RegExp(r'^([A-Z]+\d+)-(\d+)$').firstMatch(number);
    final rarity = printing.rarity?.trim().toUpperCase().replaceFirst(
      RegExp(r'^P-'),
      '',
    );
    if (tags == null || parts == null || rarity == null) {
      return SourceResult(
        marketplace: marketplace,
        status: SourceStatus.insufficientEvidence,
        reason: tags == null
            ? 'No verified e-Starbox label for "$label" yet.'
            : parts == null
            ? 'e-Starbox lookup needs a card number like OP13-118, got $number.'
            : 'e-Starbox lookup needs the official rarity.',
      );
    }
    final set = parts.group(1)!;
    final id =
        '${set.startsWith('OP') ? set : 'OP$set'}/${parts.group(2)}$rarity';

    final candidates = <Candidate>[];
    final pages = <Map<String, Object?>>[];
    final now = _clock();
    for (var i = 0; i < maxPrints; i++) {
      final url = Uri.https('tcgkakaku.e-starbox.com', '/opc/card', {
        'no': '$id${i == 0 ? '' : i}',
      });
      final String html;
      try {
        html = await _fetch(url);
      } on PageNotFound {
        break;
      } catch (e) {
        return SourceResult.failed(marketplace, 'e-Starbox request failed: $e');
      }
      final page = parseEStarboxCard(html);
      if (page == null || page.number != number || page.prices.isEmpty) {
        continue;
      }
      pages.add(page.toJson());
      final exact = page.rarityCode == rarity && _sameTags(page.tags, tags);
      final pageLabel = '${page.name} [${page.rarityLine}]';
      candidates.add(
        Candidate(
          exact: exact,
          observations: [
            for (final p in page.prices)
              PriceSource(
                name: 'e-Starbox',
                marketplace: 'e-Starbox',
                type: SourceType.priceComparison,
                price: p.price.toDouble(),
                currency: 'JPY',
                isGraded: false,
                url: url.toString(),
                title: '$pageLabel via ${p.shop}',
                sourceLabel: pageLabel,
                matchConfidence: exact ? 1.0 : null,
                observedAt: p.updated ?? now,
                usedInEstimate: false,
              ),
          ],
        ),
      );
    }
    return resolveCandidates(
      marketplace: marketplace,
      printingLabel: label,
      number: number,
      raw: jsonEncode(pages),
      candidates: candidates,
    );
  }
}

/// Our printing → the tags e-Starbox shows after the rarity (`シークレットレア
/// / パラレル`). Keyed by the variant's name, or its family code when it has
/// none. Verified against real pages (2026-10-05): the regular print shows no
/// tag, a parallel shows `パラレル`, EB04-061's crew-background print shows
/// `海賊団パラレル`. A printing without an entry is never priced from here.
const _printTags = <String, List<String>>{
  'BASE': <String>[],
  'PARALLEL': ['パラレル'],
  'PIRATE_CREW_SUPER_PARALLEL': ['海賊団パラレル'],
};

bool _sameTags(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);

const _rarityCodes = {
  'リーダー': 'L',
  'コモン': 'C',
  'アンコモン': 'UC',
  'レア': 'R',
  'スーパーレア': 'SR',
  'シークレットレア': 'SEC',
  'プロモ': 'P',
};

class EStarboxPrice {
  const EStarboxPrice(this.price, this.shop, this.updated);
  final int price;
  final String shop;
  final DateTime? updated;
}

class EStarboxCard {
  const EStarboxCard({
    required this.name,
    required this.number,
    required this.rarityLine,
    required this.prices,
    this.expansion,
  });

  /// The name with its marketplace suffix, e.g. `モンキー・Ｄ・ルフィ（背景海賊団）`.
  final String name;
  final String number;

  /// Exactly as shown: `シークレットレア / 海賊団パラレル`.
  final String rarityLine;
  final String? expansion;

  /// Shop sale prices (買取 rows excluded).
  final List<EStarboxPrice> prices;

  List<String> get _segments =>
      rarityLine.split('/').map((s) => s.trim()).toList();

  /// `SEC` for シークレットレア; null for a rarity word we don't know.
  String? get rarityCode => _rarityCodes[_segments.first];

  List<String> get tags => _segments.skip(1).toList();

  Map<String, Object?> toJson() => {
    'name': name,
    'number': number,
    'rarity_line': rarityLine,
    'expansion': expansion,
    'sale_prices': [
      for (final p in prices) {'shop': p.shop, 'price_jpy': p.price},
    ],
  };
}

/// One e-Starbox card page, or null if it isn't one.
EStarboxCard? parseEStarboxCard(String html) {
  final name = RegExp(
    r'class="kana">[^<]*</span><br><a[^>]*>([^<]*)</a>',
  ).firstMatch(html)?.group(1)?.trim();
  final line = RegExp(
    r'([A-Z0-9]+-\d+)<span class="item-separator"></span>([^<]*)<',
  ).firstMatch(html);
  if (name == null || line == null) return null;
  final expansion = RegExp(
    r'expansion\?id=[A-Za-z0-9]+">([^<]*)</a>',
  ).firstMatch(html)?.group(1)?.trim();

  // Only the sale table: it ends where the buyback table starts.
  final start = html.indexOf('sale-price-table');
  final end = html.indexOf('buy-price-table');
  final sale = start < 0
      ? ''
      : html.substring(start, end > start ? end : html.length);
  final prices = <EStarboxPrice>[];
  for (final row in sale.split('<tr>').skip(1)) {
    final price = RegExp(r'&yen;\s*([\d,]+)').firstMatch(row);
    if (price == null) continue;
    final shop = RegExp(
      r'<a[^>]*>\s*([^<]*?)\s*(?:&nbsp;)?\s*<i',
    ).firstMatch(row)?.group(1)?.trim();
    final date = RegExp(r'(\d{4})\.(\d{2})\.(\d{2})').firstMatch(row);
    prices.add(
      EStarboxPrice(
        int.parse(price.group(1)!.replaceAll(',', '')),
        (shop == null || shop.isEmpty) ? 'unknown shop' : shop,
        date == null
            ? null
            : DateTime(
                int.parse(date.group(1)!),
                int.parse(date.group(2)!),
                int.parse(date.group(3)!),
              ),
      ),
    );
  }
  return EStarboxCard(
    name: name,
    number: line.group(1)!,
    rarityLine: line.group(2)!.trim(),
    expansion: expansion,
    prices: prices,
  );
}
