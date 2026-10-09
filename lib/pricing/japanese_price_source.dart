import 'dart:convert';
import 'dart:io';

import 'price_research_service.dart';

/// One Japanese marketplace, asked about one exact physical printing. Each
/// implementation owns its site's search, parsing and its verified labels for
/// our printings; none of that leaks into [PrintingDescriptor]. A source never
/// returns a price for a printing it can't verify — a card number alone is
/// never enough.
abstract interface class JapanesePriceSource {
  /// Display name, e.g. `CardRush`. Stored on every observation.
  String get marketplace;

  Future<SourceResult> research(PrintingDescriptor printing);
}

/// What one marketplace found. [observations] holds every listing seen for the
/// card number: the ones that are this printing carry
/// [PriceSource.usedInEstimate]; the rest are kept as evidence with a
/// [PriceSource.notUsedReason].
class SourceResult {
  const SourceResult({
    required this.marketplace,
    required this.status,
    this.reason = '',
    this.observations = const [],
    this.raw = '',
  });

  factory SourceResult.failed(String marketplace, String reason) =>
      SourceResult(
        marketplace: marketplace,
        status: SourceStatus.retrievalFailed,
        reason: reason,
      );

  final String marketplace;
  final SourceStatus status;
  final String reason;
  final List<PriceSource> observations;

  /// The pages' data as read, kept as evidence.
  final String raw;

  SourceReport get report =>
      SourceReport(marketplace: marketplace, status: status, reason: reason);
}

/// A page the marketplace says doesn't exist (HTTP 404): an absence, not a
/// failure.
class PageNotFound implements Exception {
  const PageNotFound(this.url);
  final Uri url;
  @override
  String toString() => 'Page not found: $url';
}

/// GET a page as text. [PageNotFound] on 404, [HttpException] on any other
/// non-200.
Future<String> fetchPage(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) throw PageNotFound(url);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// A listing (or a page of shop prices for one card) and what we concluded
/// about it, before deciding which one counts.
class Candidate {
  const Candidate({
    required this.observations,
    required this.exact,
    this.excludedReason,
    this.soldOut = false,
  });

  final List<PriceSource> observations;

  /// Verified to be the requested printing.
  final bool exact;

  /// Exact printing, but not the kind of listing a price may come from
  /// (graded, lower condition, …).
  final String? excludedReason;
  final bool soldOut;

  bool get eligible => exact && excludedReason == null;
}

/// Turns candidates into the marketplace's verdict. Exactly one eligible
/// listing of the printing is a match; none is no-match; several equally good
/// ones are ambiguous and nothing is priced. An in-stock listing beats
/// sold-out ones of the same printing.
SourceResult resolveCandidates({
  required String marketplace,
  required List<Candidate> candidates,
  required String printingLabel,
  required String number,
  String raw = '',
}) {
  final eligible = candidates.where((c) => c.eligible).toList();
  final inStock = eligible.where((c) => !c.soldOut).toList();
  final pool = inStock.isNotEmpty ? inStock : eligible;
  final chosen = pool.length == 1 ? pool.single : null;

  PriceSource verdict(Candidate c, PriceSource o) {
    if (identical(c, chosen)) return o.withUse(true);
    if (!c.exact) return o.withUse(false, 'different printing');
    if (c.excludedReason != null) return o.withUse(false, c.excludedReason);
    if (pool.length > 1) return o.withUse(false, 'ambiguous: several listings');
    return o.withUse(false, 'sold out (another listing is in stock)');
  }

  final observations = [
    for (final c in candidates)
      for (final o in c.observations) verdict(c, o),
  ];
  if (chosen != null) {
    return SourceResult(
      marketplace: marketplace,
      status: SourceStatus.match,
      observations: observations,
      raw: raw,
      reason: chosen.soldOut ? 'only a sold-out listing' : '',
    );
  }
  if (pool.length > 1) {
    return SourceResult(
      marketplace: marketplace,
      status: SourceStatus.insufficientEvidence,
      reason:
          '${pool.length} equally good $marketplace listings of $number match '
          '"$printingLabel"; can\'t tell which is the card.',
      observations: observations,
      raw: raw,
    );
  }
  final exactButExcluded = candidates.where((c) => c.exact).length;
  return SourceResult(
    marketplace: marketplace,
    status: SourceStatus.noMatch,
    reason: candidates.isEmpty
        ? '$marketplace lists no $number.'
        : exactButExcluded > 0
        ? '$marketplace has "$printingLabel" of $number only as graded or '
              'lower-condition copies.'
        : '$marketplace has no "$printingLabel" of $number '
              '(${candidates.length} other printings listed).',
    observations: observations,
    raw: raw,
  );
}
