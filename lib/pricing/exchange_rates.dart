import 'dart:convert';
import 'dart:io';

/// Live ECB reference rates from frankfurter.dev (free, no key): how many
/// units of each currency one unit of [base] buys, e.g. `{'EUR': 0.89}` for
/// base `USD`. A source's price in that currency is `price / rates[currency]`.
///
/// Returns an empty map if the lookup fails — callers then fall back to
/// ignoring other-currency sources rather than guessing a rate.
Future<Map<String, double>> fetchRates(String base) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(
      Uri.parse('https://api.frankfurter.dev/v1/latest?base=$base'),
    );
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const {};
    final json =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    return {
      for (final e in (json['rates'] as Map<String, dynamic>).entries)
        e.key: (e.value as num).toDouble(),
    };
  } catch (_) {
    return const {};
  } finally {
    client.close(force: true);
  }
}
