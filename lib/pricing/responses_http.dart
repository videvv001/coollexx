import 'dart:convert';
import 'dart:io';

/// POSTs [body] to a Responses-API-compatible endpoint (OpenAI and DeepSeek
/// both speak this format). Returns status code + raw body; throws only on
/// transport errors (DNS, TLS, timeout).
Future<(int, String)> postResponses(
  Uri endpoint,
  String apiKey,
  Map<String, Object?> body, {
  required Duration timeout,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(endpoint);
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

/// The concatenated `output_text` of every `message` output item.
String responsesOutputText(Map<String, dynamic> json) {
  final text = StringBuffer();
  for (final o in (json['output'] as List?) ?? const []) {
    if (o is! Map || o['type'] != 'message') continue;
    for (final c in (o['content'] as List?) ?? const []) {
      if (c is Map && c['type'] == 'output_text') text.write(c['text']);
    }
  }
  return text.toString();
}
