import 'dart:convert';

import 'japanese_price_source.dart';
import 'price_research_service.dart';

/// YuYu-tei (遊々亭), read through its own search: one plain HTTP GET, no AI.
/// The search matches the card number across every set — which matters,
/// because a printing can be sold in a different pack than its number says
/// (EB04-061's crew-background print is an OP17 pack card, listed only on
/// OP17's page, never on EB04's).
///
/// Yuyu-tei prices are a shop's asking price ([SourceType.currentListing]), in
/// yen. Its `(…)` name suffixes are its own vocabulary; a printing is priced
/// only through a verified label in [_aliases] (see there), and never because
/// it happens to be the only alternate listed.
class YuyuteiPriceSource implements JapanesePriceSource {
  YuyuteiPriceSource({
    Future<String> Function(Uri url)? fetch,
    DateTime Function()? clock,
  }) : _fetch = fetch ?? fetchPage,
       _clock = clock ?? DateTime.now;

  final Future<String> Function(Uri url) _fetch;
  final DateTime Function() _clock;

  @override
  String get marketplace => 'Yuyu-tei';

  @override
  Future<SourceResult> research(PrintingDescriptor printing) async {
    final number = printing.cardNumber.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+-\d+$').hasMatch(number)) {
      return SourceResult(
        marketplace: marketplace,
        status: SourceStatus.insufficientEvidence,
        reason:
            'Yuyu-tei lookup needs a card number like OP13-118, got $number.',
      );
    }
    final url = Uri.https('yuyu-tei.jp', '/sell/opc/s/search', {
      'search_word': number,
    });
    final String html;
    try {
      html = await _fetch(url);
    } catch (e) {
      return SourceResult.failed(marketplace, 'Yuyu-tei request failed: $e');
    }
    final entries = parseYuyuteiListing(
      html,
    ).where((e) => e.number == number).toList();
    final raw = jsonEncode([for (final e in entries) e.toJson()]);

    final key = printing.variant.name ?? printing.variant.family.code;
    final signature = _aliases[key];
    final now = _clock();
    final label = printing.variant.displayLabel;

    PriceSource observe(YuyuteiEntry e, {required bool exact}) => PriceSource(
      name: 'Yuyu-tei',
      marketplace: 'Yuyu-tei',
      type: SourceType.currentListing,
      price: e.price.toDouble(),
      currency: 'JPY',
      isGraded: false,
      url: e.url,
      title: '${e.name} [${e.rarity}]${e.soldOut ? ' (sold out)' : ''}',
      sourceLabel: e.name,
      matchConfidence: exact ? 1.0 : null,
      soldOut: e.soldOut,
      observedAt: now,
      usedInEstimate: false,
    );

    if (signature == null) {
      return SourceResult(
        marketplace: marketplace,
        status: SourceStatus.insufficientEvidence,
        reason:
            'No verified Yuyu-tei label for "$label" yet, so none of the '
            '${entries.length} printings of $number there can be matched to it.',
        observations: [
          for (final e in entries)
            observe(
              e,
              exact: false,
            ).withUse(false, 'no verified label for this printing'),
        ],
        raw: raw,
      );
    }
    bool isExact(YuyuteiEntry e) =>
        _sameLabels(e.suffixes, signature) &&
        (printing.rarity == null ||
            _baseRarity(e.rarity) == _baseRarity(printing.rarity!));
    return resolveCandidates(
      marketplace: marketplace,
      printingLabel: label,
      number: number,
      raw: raw,
      candidates: [
        for (final e in entries)
          Candidate(
            observations: [observe(e, exact: isExact(e))],
            exact: isExact(e),
            soldOut: e.soldOut,
          ),
      ],
    );
  }
}

/// Our printing → the `(…)` suffix labels Yuyu-tei puts on that printing, in
/// order. Keyed by the variant's name, or its family code when it has none.
/// Only labels verified against real listings (2026-10-05): the regular
/// printing has no suffix, a parallel is `(パラレル)`, and EB04-061's
/// crew-background print is `(パラレル)(海賊団スーパーパラレル)`. A printing
/// without an entry here is never priced from Yuyu-tei — a missing label
/// means "can't tell", never "the closest alternate".
const _aliases = <String, List<String>>{
  'BASE': <String>[],
  'PARALLEL': ['パラレル'],
  'PIRATE_CREW_SUPER_PARALLEL': ['パラレル', '海賊団スーパーパラレル'],
};

bool _sameLabels(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);

/// Yuyu-tei lists a parallel's rarity as `P-SEC`; the card itself prints `SEC`.
String _baseRarity(String rarity) =>
    rarity.trim().toUpperCase().replaceFirst(RegExp(r'^P-'), '');

class YuyuteiEntry {
  const YuyuteiEntry({
    required this.number,
    required this.rarity,
    required this.name,
    required this.price,
    required this.soldOut,
    required this.url,
  });

  final String number;
  final String rarity;
  final String name;

  /// Yen.
  final int price;
  final bool soldOut;
  final String url;

  /// Every "(…)" label on the name, in order: `X(パラレル)(スーパーパラレル)` →
  /// `[パラレル, スーパーパラレル]`. Empty for a regular printing.
  List<String> get suffixes => [
    for (final m in RegExp(r'[(（]([^)）]*)[)）]').allMatches(name))
      m.group(1)!.trim(),
  ];

  bool get isRegular => suffixes.isEmpty;

  Map<String, Object?> toJson() => {
    'number': number,
    'rarity': rarity,
    'name': name,
    'price_jpy': price,
    'sold_out': soldOut,
    'url': url,
  };
}

/// Every card on a Yuyu-tei set or search page (`/sell/opc/s/op13`,
/// `/sell/opc/s/search?search_word=…`). Cards the page doesn't give a price
/// for are skipped.
List<YuyuteiEntry> parseYuyuteiListing(String html) {
  final entries = <YuyuteiEntry>[];
  for (final block in html.split('card-product position-relative').skip(1)) {
    final alt = RegExp(
      r'alt="(\S+)\s+(\S+)\s+([^"]+)" class="card img-fluid"',
    ).firstMatch(block);
    final price = RegExp(
      r'<strong\s+class="d-block text-end[^"]*">\s*([\d,]+)\s*円',
    ).firstMatch(block);
    final link = RegExp(
      r'href="(https://yuyu-tei\.jp/sell/opc/card/[^"]+)"',
    ).firstMatch(block);
    if (alt == null || price == null || link == null) continue;
    entries.add(
      YuyuteiEntry(
        number: alt.group(1)!.toUpperCase(),
        rarity: alt.group(2)!,
        name: alt.group(3)!.trim(),
        price: int.parse(price.group(1)!.replaceAll(',', '')),
        // The card's own tag opens the block: `... mt-4   sold-out ">`.
        soldOut: block.substring(0, block.indexOf('>')).contains('sold-out'),
        url: link.group(1)!,
      ),
    );
  }
  return entries;
}
