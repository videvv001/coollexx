import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/binder_page_detector.dart';
import '../../pricing/card_identifier.dart';
import '../../pricing/card_recognition_service.dart';
import '../../pricing/price_research_service.dart';
import '../../state/ai_settings.dart';
import 'ai_scan_test_screen.dart';

/// How many AI calls run at once: enough to make a nine-card page quick,
/// few enough not to trip provider rate limits.
const _concurrency = 3;

/// Testing-mode binder scan: one page photo → on-device card detection →
/// AI recognition of every card → optional price research for the lot. Saves
/// nothing; tap a card to open it in the single-card screen to correct it.
class AiBinderTestScreen extends StatefulWidget {
  const AiBinderTestScreen({super.key});

  @override
  State<AiBinderTestScreen> createState() => _AiBinderTestScreenState();
}

class _Card {
  _Card(this.path);

  final String path;
  IdentificationResult? ident;
  PriceResearchResult? price;
  bool researching = false;

  /// The resolved printing when identified, else the unresolved prediction.
  PrintingDescriptor? get printing => ident?.printing;

  /// Only a confident match is priced in bulk; the rest need a human look
  /// first (tap the card), same rule as the single-card screen.
  bool get canResearch =>
      ident?.status == RecognitionStatus.identified && price == null;
}

class _AiBinderTestScreenState extends State<AiBinderTestScreen> {
  final _cards = <_Card>[];
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _deleteCrops();
    super.dispose();
  }

  void _deleteCrops() {
    for (final c in _cards) {
      File(c.path).delete().ignore();
    }
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null || !mounted) return;
    final settings = context.read<AiSettings>();
    _deleteCrops();
    setState(() {
      _cards.clear();
      _error = null;
      _busy = 'Finding the cards on the page…';
    });
    final BinderPageScan scan;
    try {
      scan = await scanBinderPage(file.path);
    } on BinderPageDecodeException catch (e) {
      return _fail('$e');
    }
    if (!mounted) return;
    if (scan.cardCount == 0) return _fail('No cards found on that page.');
    final dir = await getTemporaryDirectory();
    final cards = <_Card>[];
    for (final jpg in scan.cardJpgs) {
      final f = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
      await f.writeAsBytes(jpg);
      cards.add(_Card(f.path));
    }
    if (!mounted) return;
    setState(() => _cards.addAll(cards));

    final identifier = settings.identifier;
    var done = 0;
    await _forEachLimited(cards, (card) async {
      // ponytail: two cards of one number read at the same moment each run
      // printing research; the cache only helps the second time.
      card.ident = await identifier.identify([card.path]);
      done++;
      if (mounted) {
        setState(
          () => _busy =
              'Identifying with ${identifier.recognition.provider}… $done / ${cards.length}',
        );
      }
    });
    if (mounted) setState(() => _busy = null);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = message;
    });
  }

  Future<void> _researchAll() async {
    final service = context.read<AiSettings>().priceResearchService;
    final todo = _cards.where((c) => c.canResearch).toList();
    var done = 0;
    String progress() =>
        'Researching prices with ${service.provider}… $done / ${todo.length}';
    setState(() => _busy = progress());
    await _forEachLimited(todo, (card) async {
      if (mounted) setState(() => card.researching = true);
      card.price = await service.research(
        PriceResearchRequest(printing: card.printing!),
      );
      await recordObservations(card.printing!, card.price!, service.provider);
      done++;
      if (mounted) {
        setState(() {
          card.researching = false;
          _busy = progress();
        });
      }
    });
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AiSettings>();
    final text = Theme.of(context).textTheme;
    final pending = _cards.where((c) => c.canResearch).length;
    final needsLook = _cards
        .where(
          (c) =>
              c.ident != null &&
              c.ident!.status != RecognitionStatus.identified,
        )
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('AI binder scan test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Recognition: ${settings.recognitionProvider.label} · '
            'Price research: ${settings.researchProvider.label}',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy == null
                      ? () => _pick(ImageSource.camera)
                      : null,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Photo of page'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy == null
                      ? () => _pick(ImageSource.gallery)
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Upload'),
                ),
              ),
            ],
          ),
          if (_busy != null) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_busy!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_cards.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '${_cards.length} cards'
              '${needsLook > 0 ? ' · $needsLook need a look' : ''}',
              style: text.titleSmall,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy == null && pending > 0 ? _researchAll : null,
              child: Text('Research prices for $pending identified'),
            ),
            for (final c in _cards) _CardTile(card: c),
          ],
        ],
      ),
    );
  }
}

/// Runs [fn] over [items], at most [_concurrency] at a time.
Future<void> _forEachLimited<T>(
  List<T> items,
  Future<void> Function(T) fn,
) async {
  final queue = Queue.of(items);
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      await fn(queue.removeFirst());
    }
  }

  await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});

  final _Card card;

  @override
  Widget build(BuildContext context) {
    final r = card.ident;
    final pr = card.printing;
    final (label, color) = switch (r?.status) {
      null => ('Recognizing…', Colors.grey),
      RecognitionStatus.identified => ('Identified', Colors.green),
      RecognitionStatus.verificationRequired => ('Needs a look', Colors.orange),
      RecognitionStatus.unrecognized => ('Not recognized', Colors.red),
      RecognitionStatus.failed => ('Failed', Colors.red),
    };
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(File(card.path), width: 44, fit: BoxFit.cover),
        ),
        title: Text(pr?.name ?? label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pr != null) Text(label, style: TextStyle(color: color)),
            if (pr != null)
              Text(
                [
                  pr.cardNumber,
                  pr.language,
                  pr.variant.displayLabel,
                ].join(' · '),
              ),
            if (r != null && r.status != RecognitionStatus.identified)
              Text(r.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (card.researching) const Text('Researching price…'),
            if (card.price != null) Text(_priceLine(card.price!)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        // Edits made there aren't carried back: this list is a read-only
        // overview, the single-card screen is where a card gets corrected.
        onTap: r == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AiScanTestScreen(
                    imagePath: card.path,
                    identification: r,
                    price: card.price,
                  ),
                ),
              ),
      ),
    );
  }
}

String _priceLine(PriceResearchResult r) => switch (r) {
  PriceResearchSuccess s =>
    '${formatMoney(s.estimatedPrice, s.currency)} · '
        '${s.observationCount} sources · ${formatPct(s.confidence)} confidence'
        '${s.lastSold == null ? '' : ' · last sold ${formatMoney(s.lastSold!.price, s.currency)}'}'
        '${s.lowestListing == null ? '' : ' · listed ${formatMoney(s.lowestListing!.price, s.currency)}'}',
  InsufficientEvidence s when s.sources.isNotEmpty =>
    '${s.sources.length} listings seen, none this exact printing: tap to see',
  InsufficientEvidence _ => 'Not enough price evidence',
  PrintingVerificationRequired _ => 'Price research: printing needs checking',
  RetrievalFailed s => 'Price research failed: ${s.reason}',
};
