import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/printing_candidate_repository.dart';
import '../dev_secrets.dart';
import '../pricing/card_identifier.dart';
import '../pricing/card_recognition_service.dart';
import '../pricing/cardrush_price_source.dart';
import '../pricing/estarbox_price_source.dart';
import '../pricing/japanese_price_research_service.dart';
import '../pricing/price_research_service.dart';
import '../pricing/printing_research_service.dart';
import '../pricing/printing_resolution_service.dart';
import '../pricing/responses_card_recognition_service.dart';
import '../pricing/responses_price_research_service.dart';
import '../pricing/yuyutei_price_service.dart';

const _recognitionKey = 'ai_recognition_provider';
const _researchKey = 'ai_research_provider';

enum AiProvider {
  openai('OpenAI'),
  deepseek('DeepSeek');

  final String label;
  const AiProvider(this.label);

  bool get hasKey => switch (this) {
    AiProvider.openai => openaiApiKey.isNotEmpty,
    AiProvider.deepseek => deepseekApiKey.isNotEmpty,
  };

  static AiProvider? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Testing-mode switches for which AI reads card photos and which researches
/// prices. Whatever is picked for research, a result with no proof of a
/// completed live web search is rejected, never shown as a price. Same
/// load/persist shape as `OcrSettings`.
class AiSettings extends ChangeNotifier {
  AiSettings() {
    _load();
  }

  AiProvider _recognitionProvider = AiProvider.openai;
  AiProvider _researchProvider = AiProvider.openai;
  AiProvider get recognitionProvider => _recognitionProvider;
  AiProvider get researchProvider => _researchProvider;

  CardRecognitionService get recognitionService =>
      switch (_recognitionProvider) {
        AiProvider.openai => OpenAICardRecognitionService(apiKey: openaiApiKey),
        AiProvider.deepseek => DeepSeekCardRecognitionService(
          apiKey: deepseekApiKey,
        ),
      };

  /// Photo → predicted printing → resolved against the card's known printings.
  /// Printing research always uses OpenAI: it needs a live web search, which
  /// DeepSeek's API ignores.
  CardIdentifier get identifier => CardIdentifier(
    recognition: recognitionService,
    resolver: PrintingResolutionService(
      research: OpenAIPrintingResearchService(apiKey: openaiApiKey),
      cache: PrintingCandidateRepository(),
    ),
  );

  /// Japanese One Piece is priced from Japanese marketplaces (Yuyu-tei,
  /// CardRush, e-Starbox — no AI involved), with the picked provider's live
  /// web search as the fallback when none of them has the exact printing.
  /// Everything else goes to that provider.
  PriceResearchService get priceResearchService => JapanesePriceResearchService(
    sources: [
      YuyuteiPriceSource(),
      CardRushPriceSource(),
      EStarboxPriceSource(),
    ],
    fallback: switch (_researchProvider) {
      AiProvider.openai => OpenAIPriceResearchService(apiKey: openaiApiKey),
      AiProvider.deepseek => DeepSeekPriceResearchService(
        apiKey: deepseekApiKey,
      ),
    },
  );

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _recognitionProvider =
        AiProvider.fromName(prefs.getString(_recognitionKey)) ??
        _recognitionProvider;
    _researchProvider =
        AiProvider.fromName(prefs.getString(_researchKey)) ?? _researchProvider;
    notifyListeners();
  }

  Future<void> setRecognitionProvider(AiProvider value) async {
    _recognitionProvider = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recognitionKey, value.name);
  }

  Future<void> setResearchProvider(AiProvider value) async {
    _researchProvider = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_researchKey, value.name);
  }
}
