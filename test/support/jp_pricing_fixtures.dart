// Shared by the Japanese pricing tests: the real, saved marketplace pages for
// EB04-061 (captured 2026-10-05, trimmed) behind fake fetchers, plus the three
// EB04-061 printings as descriptors. Nothing here touches the network.

import 'dart:io';

import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/japanese_price_source.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const basePrinting = PrintingVariant(family: VariantFamily.base);
const parallelPrinting = PrintingVariant(family: VariantFamily.parallel);

/// EB04-061's crew-background print (sold as an OP17 pack card).
const crewPrinting = PrintingVariant(
  family: VariantFamily.superParallel,
  name: 'PIRATE_CREW_SUPER_PARALLEL',
  artwork: 'Gear 5 Luffy with the Straw Hat crew behind him',
);
const redMangaPrinting = PrintingVariant(
  family: VariantFamily.superParallel,
  name: 'RED_MANGA_RARE',
);

PrintingDescriptor printing(
  PrintingVariant variant, {
  String number = 'EB04-061',
  String? rarity = 'SEC',
  String language = 'Japanese',
  TcgGame game = TcgGame.onePiece,
}) => PrintingDescriptor(
  game: game,
  name: 'モンキー・D・ルフィ',
  cardNumber: number,
  language: language,
  rarity: rarity,
  variant: variant,
);

PriceResearchRequest request(PrintingVariant variant, {String? number}) =>
    PriceResearchRequest(
      printing: printing(variant, number: number ?? 'EB04-061'),
    );

/// Fetchers serving the saved real pages.
Future<String> Function(Uri) yuyuteiFetch([List<Uri>? log]) => (u) async {
  log?.add(u);
  return fixture('yuyutei_search_eb04_061.html');
};

Future<String> Function(Uri) cardRushFetch([List<Uri>? log]) => (u) async {
  log?.add(u);
  return fixture('cardrush_eb04_061.html');
};

/// e-Starbox serves each print's own page; any other id is a 404.
Future<String> Function(Uri) eStarboxFetch([List<Uri>? log]) {
  const pages = {
    'OPEB04/061SEC': 'estarbox_eb04_061_sec.html',
    'OPEB04/061SEC1': 'estarbox_eb04_061_sec1.html',
    'OPEB04/061SEC2': 'estarbox_eb04_061_sec2.html',
    'OPEB04/061SEC3': 'estarbox_eb04_061_sec3.html',
  };
  return (u) async {
    log?.add(u);
    final file = pages[u.queryParameters['no']];
    if (file == null) throw PageNotFound(u);
    return fixture(file);
  };
}

/// A YuYu-tei search page made of the given listings.
String yuyuteiPage(List<(String, String, String, int, bool)> cards) => [
  for (final (number, rarity, name, price, soldOut) in cards)
    '''<div
class="card-product position-relative mt-4   ${soldOut ? 'sold-out ' : ''}"><div class="starbtn"></div>
<a
href="https://yuyu-tei.jp/sell/opc/card/x/$number"><div
class="position-relative product-img">
<img
src="https://card.yuyu-tei.jp/x.jpg" alt="$number $rarity $name" class="card img-fluid"/></div>
</a>
<strong
class="d-block text-end ">
$price 円
</strong></div>''',
].join('\n');

/// A CardRush result cell.
String cardRushCell(int id, String title, int price, {bool inStock = true}) =>
    '''<li class="list_item_cell list_item_$id ">
<div class="item_data" data-product-id="$id">
<a href="https://www.cardrush-op.jp/product/$id" class="item_data_link">
<p class="item_name"><span class="goods_name">$title</span> <wbr /><span class="model_number"><span class="bracket">[</span><span class="model_number_value">x</span><span class="bracket">]</span></span></p>
<div class="item_info"><div class="price"><p class="selling_price"><span class="figure">$price円</span></p></div>
<p class="stock">${inStock ? '在庫数 3枚' : '在庫なし'}</p></div>
</a></div></li>''';

/// A source that reports a fixed verdict, for orchestrator tests.
class FakeSource implements JapanesePriceSource {
  FakeSource(this.marketplace, this._result);

  @override
  final String marketplace;
  final Future<SourceResult> Function(PrintingDescriptor) _result;
  int calls = 0;

  @override
  Future<SourceResult> research(PrintingDescriptor p) {
    calls++;
    return _result(p);
  }
}

/// A listing observation, used by the fakes.
PriceSource observation(
  String marketplace,
  num price, {
  bool used = true,
  bool soldOut = false,
  SourceType type = SourceType.currentListing,
}) => PriceSource(
  name: marketplace,
  marketplace: marketplace,
  type: type,
  price: price.toDouble(),
  currency: 'JPY',
  isGraded: false,
  url: 'https://example.test/$marketplace/${price.round()}',
  usedInEstimate: used,
  matchConfidence: used ? 1.0 : null,
  soldOut: soldOut,
);

SourceResult matched(String marketplace, List<PriceSource> observations) =>
    SourceResult(
      marketplace: marketplace,
      status: SourceStatus.match,
      observations: observations,
    );

SourceResult noMatch(String marketplace) => SourceResult(
  marketplace: marketplace,
  status: SourceStatus.noMatch,
  reason: 'nothing',
);

/// The price research fallback (the live web search) as a fake.
class FakeWebResearch implements PriceResearchService {
  FakeWebResearch(this.result);

  PriceResearchResult result;
  PriceResearchRequest? got;
  int calls = 0;

  @override
  String get provider => 'FakeWeb';

  @override
  Future<PriceResearchResult> research(PriceResearchRequest request) async {
    calls++;
    got = request;
    return result;
  }
}
