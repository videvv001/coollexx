import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/price_observation_repository.dart';
import '../../models/printing_candidate.dart';
import '../../models/printing_variant.dart';
import '../../models/tcg_game.dart';
import '../../pricing/card_identifier.dart';
import '../../pricing/card_recognition_service.dart';
import '../../pricing/price_research_service.dart';
import '../../pricing/printing_resolution_service.dart';
import '../../pricing/responses_price_research_service.dart';
import '../../state/ai_settings.dart';
import '../../utils/formatting.dart';

/// Testing-mode playground: photo → recognition (provider from
/// [AiSettings]) → printing resolution against the card's known printings →
/// editable printing → live price research. Saves nothing.
///
/// Opened from the binder scan with a card that's already been identified
/// ([imagePath] + [identification], and [price] if it was researched) so
/// nothing is paid for twice.
class AiScanTestScreen extends StatefulWidget {
  const AiScanTestScreen({
    super.key,
    this.imagePath,
    this.identification,
    this.price,
  });

  final String? imagePath;
  final IdentificationResult? identification;
  final PriceResearchResult? price;

  @override
  State<AiScanTestScreen> createState() => _AiScanTestScreenState();
}

class _AiScanTestScreenState extends State<AiScanTestScreen> {
  String? _imagePath;
  String? _busy; // what's running, for the progress label
  IdentificationResult? _ident;
  PriceResearchResult? _price;

  TcgGame? _game;
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _language = TextEditingController();
  final _set = TextEditingController();
  final _rarity = TextEditingController();
  VariantFamily _family = VariantFamily.unknown;
  final _variantName = TextEditingController();
  final _artwork = TextEditingController();

  @override
  void initState() {
    super.initState();
    _imagePath = widget.imagePath;
    _price = widget.price;
    final r = widget.identification;
    if (r != null) _applyIdentification(r);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _number,
      _language,
      _set,
      _rarity,
      _variantName,
      _artwork,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null) return;
    setState(() {
      _imagePath = file.path;
      _ident = null;
      _price = null;
    });
    await _recognize();
  }

  Future<void> _recognize() async {
    final identifier = context.read<AiSettings>().identifier;
    setState(
      () => _busy = 'Reading the photo with ${identifier.recognition.provider}…',
    );
    final read = await identifier.recognition.recognize([_imagePath!]);
    if (!mounted) return;
    setState(() => _busy = 'Resolving the exact printing…');
    final result = await identifier.resolveRecognition(read);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _applyIdentification(result);
    });
  }

  /// Fills the editable fields from [result] (the resolved printing when
  /// there is one). Call inside setState (or from initState).
  void _applyIdentification(IdentificationResult result) {
    final p = result.printing;
    _ident = result;
    _game = p?.game;
    _name.text = p?.name ?? '';
    _number.text = p?.cardNumber ?? '';
    _language.text = p?.language ?? '';
    _set.text = p?.setCode ?? '';
    _rarity.text = p?.rarity ?? '';
    _family = p?.variant.family ?? VariantFamily.unknown;
    _variantName.text = p?.variant.name ?? '';
    _artwork.text = p?.variant.artwork ?? '';
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  bool get _canResearch =>
      _game != null &&
      _name.text.trim().isNotEmpty &&
      _number.text.trim().isNotEmpty &&
      _language.text.trim().isNotEmpty;

  /// The printing as currently typed. Exactly what the identification
  /// resolved (and so its aliases) while the variant is untouched; once the
  /// user edits it, it's their confirmation instead.
  PrintingDescriptor _descriptor() {
    final variant = PrintingVariant(
      family: _family,
      name: normalizeVariantName(_variantName.text),
      artwork: _opt(_artwork),
    );
    final resolved = _ident?.status == RecognitionStatus.identified
        ? _ident!.printing
        : null;
    final untouched = resolved != null && resolved.variant == variant;
    return PrintingDescriptor(
      game: _game!,
      name: _name.text.trim(),
      cardNumber: _number.text.trim(),
      language: _language.text.trim(),
      setCode: _opt(_set),
      rarity: _opt(_rarity),
      variant: variant,
      source: untouched ? PrintingSource.resolved : PrintingSource.userConfirmed,
      searchAliases: untouched ? resolved.searchAliases : const [],
      excludedAliases: untouched ? resolved.excludedAliases : const [],
      visualMarkers: untouched ? resolved.visualMarkers : const [],
    );
  }

  Future<void> _research() async {
    final service = context.read<AiSettings>().priceResearchService;
    setState(() {
      _busy = 'Researching prices with ${service.provider}…';
      _price = null;
    });
    final printing = _descriptor();
    final result = await service.research(
      PriceResearchRequest(printing: printing),
    );
    await recordObservations(printing, result, service.provider);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _price = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AiSettings>();
    final text = Theme.of(context).textTheme;
    final ident = _ident;
    return Scaffold(
      appBar: AppBar(title: const Text('AI scan test')),
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
                  label: const Text('Camera'),
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
          if (_imagePath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
                height: 260,
                fit: BoxFit.contain,
              ),
            ),
          ],
          if (_busy != null) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_busy!),
          ],
          if (ident != null) ...[
            const SizedBox(height: 16),
            _RecognitionSummary(result: ident),
            if (ident.resolution != null)
              _ResolutionPanel(
                resolution: ident.resolution!,
                vision: ident.recognition,
              ),
            if (ident.status == RecognitionStatus.identified ||
                ident.status == RecognitionStatus.verificationRequired) ...[
              const SizedBox(height: 12),
              Text('Printing (edit to correct)', style: text.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<TcgGame>(
                initialValue: _game,
                decoration: const InputDecoration(labelText: 'Game'),
                items: [
                  for (final g in TcgGame.values)
                    DropdownMenuItem(value: g, child: Text(g.displayName)),
                ],
                onChanged: (g) => setState(() => _game = g),
              ),
              for (final (label, c) in [
                ('Name', _name),
                ('Card number', _number),
                ('Language', _language),
                ('Set', _set),
                ('Official rarity', _rarity),
              ])
                TextField(
                  controller: c,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {}),
                ),
              DropdownButtonFormField<VariantFamily>(
                key: ValueKey(_family),
                initialValue: _family,
                decoration: const InputDecoration(labelText: 'Printing'),
                items: [
                  for (final f in VariantFamily.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (f) =>
                    setState(() => _family = f ?? VariantFamily.unknown),
              ),
              for (final (label, c) in [
                ('Printing name (e.g. RED_MANGA_RARE)', _variantName),
                ('Artwork', _artwork),
              ])
                TextField(
                  controller: c,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy == null && _canResearch ? _research : null,
                child: Text(
                  ident.status == RecognitionStatus.identified
                      ? 'Research price'
                      : "I've checked the details — research price",
                ),
              ),
              if (_canResearch)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Price research query'),
                  children: [
                    SelectableText(
                      describeResearchTarget(
                        PriceResearchRequest(printing: _descriptor()),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
            _RawResponse(
              label: 'Raw recognition response',
              raw: ident.recognition.rawResponse,
            ),
            if (ident.resolution != null)
              _RawResponse(
                label: 'Raw printing research response',
                raw: ident.resolution!.researchRaw,
              ),
          ],
          if (_price != null) ...[
            const SizedBox(height: 16),
            _PriceSummary(result: _price!),
            _RawResponse(
              label: 'Raw research response',
              raw: _price!.rawResponse,
            ),
          ],
        ],
      ),
    );
  }
}

String formatPct(double v) => '${(v * 100).round()}%';

String formatMoney(num amount, String currency) {
  try {
    return NumberFormat.simpleCurrency(name: currency).format(amount);
  } catch (_) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }
}

class _RecognitionSummary extends StatelessWidget {
  const _RecognitionSummary({required this.result});

  final IdentificationResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.recognition;
    final (label, color) = switch (result.status) {
      RecognitionStatus.identified => ('Identified', Colors.green),
      RecognitionStatus.verificationRequired => (
        'Printing needs verification',
        Colors.orange,
      ),
      RecognitionStatus.unrecognized => ('Card not recognized', Colors.red),
      RecognitionStatus.failed => ('Recognition failed', Colors.red),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            Text('${r.provider} · ${r.model}'),
            if (r.status != RecognitionStatus.failed)
              Text('Card ${formatPct(r.cardConfidence)}'),
            if (result.evidenceNeeded != EvidenceRequest.none)
              Text('Needs: ${result.evidenceNeeded.code}'),
            if (r.printing?.variant.artwork != null)
              Text('Artwork: ${r.printing!.variant.artwork}'),
            if (result.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(result.reason),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole resolution, step by step, so a wrong printing can be traced: what
/// vision guessed and saw, which printings are known, which one fit and why,
/// and which were ruled out.
class _ResolutionPanel extends StatelessWidget {
  const _ResolutionPanel({required this.resolution, required this.vision});

  final PrintingResolution resolution;
  final RecognitionResult vision;

  @override
  Widget build(BuildContext context) {
    final r = resolution;
    final text = Theme.of(context).textTheme;
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(t, style: text.labelLarge),
    );
    String candidateLine(PrintingCandidate c) =>
        '${c.label} [${c.family.code}]'
        '${c.officialRarity == null ? '' : ' ${c.officialRarity}'}'
        '${c.marketplaceAliases.isEmpty ? '' : ' — ${c.marketplaceAliases.join(', ')}'}'
        '${c.visual.summary.isEmpty ? '' : '\n    ${c.visual.summary}'}';
    final from = r.candidatesFrom.isEmpty ? 'none' : r.candidatesFrom;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Printing resolution', style: text.titleSmall),
            head('Vision'),
            Text(
              '${r.visionPredicted.isResolved ? r.visionPredicted.displayLabel : 'no prediction'}'
              ' — ${formatPct(vision.printingConfidence)}',
            ),
            if (vision.visual.summary.isNotEmpty)
              Text('Saw: ${vision.visual.summary}'),
            head('Known printings ($from)'),
            if (r.candidates.isEmpty) const Text('None found.'),
            for (final c in r.candidates) Text('• ${candidateLine(c)}'),
            head('Resolved'),
            Text(
              r.isResolved
                  ? '${r.resolved!.label} — ${formatPct(r.confidence)}'
                  : 'Not resolved'
                        '${r.confidence > 0 ? ' (${formatPct(r.confidence)})' : ''}'
                        '${r.reason.isEmpty ? '' : ': ${r.reason}'}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: r.isResolved ? Colors.green : Colors.orange,
              ),
            ),
            if (r.reasons.isNotEmpty)
              Text('Uncertainty: ${r.reasons.map((e) => e.code).join(', ')}'),
            if (r.evidence.isNotEmpty) head('Evidence'),
            for (final e in r.evidence) Text('• $e'),
            if (r.rejected.isNotEmpty) head('Rejected'),
            for (final x in r.rejected)
              Text('• ${x.candidate.label}: ${x.reason}'),
          ],
        ),
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({required this.result});

  final PriceResearchResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = result;
    final List<Widget> body = switch (r) {
      PriceResearchSuccess s => [
        Text('Estimated market value', style: text.labelMedium),
        Text(
          formatMoney(s.estimatedPrice, s.currency),
          style: text.headlineMedium,
        ),
        Text(
          'Range ${formatMoney(s.low, s.currency)} – ${formatMoney(s.high, s.currency)}',
        ),
        Text(
          'Based on ${s.observationCount} market observations · '
          'confidence ${formatPct(s.confidence)}'
          '${s.searchCalls > 0 ? ' · ${s.searchCalls} web searches' : ''}',
        ),
        if (s.lastSold != null) Text('Last sold: ${_describe(s.lastSold!)}'),
        if (s.lowestListing != null)
          Text('Lowest listing: ${_describe(s.lowestListing!)}'),
        for (final w in s.warnings)
          Text(w, style: const TextStyle(color: Colors.orange)),
        Text('Updated ${formatLongDate(s.researchedAt)}'),
        ..._reportRows(s.reports),
        const SizedBox(height: 8),
        for (final src in _usedFirst(s.sources)) _SourceTile(source: src),
      ],
      InsufficientEvidence s => [
        const Text(
          'Not enough evidence for this exact printing',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(s.reason),
        ..._reportRows(s.reports),
        const SizedBox(height: 8),
        for (final src in _usedFirst(s.sources)) _SourceTile(source: src),
      ],
      PrintingVerificationRequired s => [
        const Text(
          'Research says the printing needs checking',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(s.reason),
      ],
      RetrievalFailed s => [
        const Text(
          'Price research failed',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red),
        ),
        Text(s.reason),
        ..._reportRows(s.reports),
      ],
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body,
        ),
      ),
    );
  }
}

/// Observations that count first, then the evidence that doesn't.
List<PriceSource> _usedFirst(List<PriceSource> sources) => [
  ...sources.where((s) => s.usedInEstimate),
  ...sources.where((s) => !s.usedInEstimate),
];

/// Where the price came from, marketplace by marketplace: an exact match, no
/// match, couldn't tell, or couldn't be read - never blurred together.
List<Widget> _reportRows(List<SourceReport> reports) {
  if (reports.isEmpty) return const [];
  return [
    const SizedBox(height: 12),
    const Text('Sources', style: TextStyle(fontWeight: FontWeight.w700)),
    for (final r in reports)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${r.marketplace}  ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: switch (r.status) {
                  SourceStatus.match => 'Exact printing found',
                  SourceStatus.noMatch => 'Exact printing not found',
                  SourceStatus.insufficientEvidence => "Couldn't tell",
                  SourceStatus.retrievalFailed => 'Retrieval failed',
                },
                style: TextStyle(
                  color: switch (r.status) {
                    SourceStatus.match => Colors.green,
                    SourceStatus.noMatch => Colors.grey,
                    SourceStatus.insufficientEvidence => Colors.orange,
                    SourceStatus.retrievalFailed => Colors.red,
                  },
                ),
              ),
              if (r.reason.isNotEmpty) TextSpan(text: '\n${r.reason}'),
            ],
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ),
  ];
}

/// Saves a research's observations to the price history. History is a record,
/// never something a screen depends on, so a failure here is only logged.
Future<void> recordObservations(
  PrintingDescriptor printing,
  PriceResearchResult result,
  String provider,
) async {
  try {
    await PriceObservationRepository().record(
      printing,
      result,
      provider: provider,
    );
  } catch (e) {
    debugPrint('Could not save price history: $e');
  }
}

/// "$139.10 (converted from €124.00)" when the page's price was in another
/// currency.
String _priceText(PriceSource s) =>
    formatMoney(s.price, s.currency) +
    (s.originalPrice == null
        ? ''
        : ' (converted from ${formatMoney(s.originalPrice!, s.originalCurrency!)})');

/// Price plus the date it was seen, e.g. "$139.10 · 1 Oct 2026".
String _describe(PriceSource s) =>
    '${_priceText(s)} · '
    '${s.observedAt == null ? 'date not stated' : formatLongDate(s.observedAt!)}';

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final PriceSource source;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${_priceText(source)} · ${source.type.code}'
        '${source.usedInEstimate ? '' : ' · NOT USED'}',
        style: source.usedInEstimate
            ? null
            : const TextStyle(color: Colors.grey),
      ),
      subtitle: Text(
        [
          source.marketplace ?? source.name,
          if (source.sourceLabel != null) source.sourceLabel!,
          if (source.condition != null) source.condition!,
          if (source.isGraded) 'graded',
          if (source.soldOut) 'sold out',
          if (source.matchConfidence != null)
            'match ${formatPct(source.matchConfidence!)}',
          if (source.notUsedReason != null) source.notUsedReason!,
          source.url,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.copy, size: 18),
      onTap: () {
        Clipboard.setData(ClipboardData(text: source.url));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Source link copied')));
      },
    );
  }
}

class _RawResponse extends StatelessWidget {
  const _RawResponse({required this.label, required this.raw});

  final String label;
  final String raw;

  @override
  Widget build(BuildContext context) {
    if (raw.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(label),
      children: [
        SelectableText(
          raw.length > 20000 ? '${raw.substring(0, 20000)}…' : raw,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ],
    );
  }
}
