import '../models/printing_variant.dart';

/// Words that help FIND listings of a printing across marketplaces that each
/// name it differently. Discovery only — nothing here ever decides that a
/// listing is the printing (each marketplace adapter holds its own verified
/// labels for that), and none of it is an official classification.
///
/// Keyed by [PrintingVariant.name] (the specific printing); a printing with no
/// entry just gets no extra terms.
const _discoveryTerms = <String, List<String>>{
  // EB04-061 crew-background print, sold as an OP17 pack card.
  'PIRATE_CREW_SUPER_PARALLEL': [
    'TEAM_SP',
    'TEAM SP',
    'SEC-SP',
    'Pirate Crew Super Parallel',
    'Pirate Crew Parallel',
    '海賊団スーパーパラレル',
    '海賊団パラレル',
    '4周年海賊団パラレル',
    '海賊団背景',
    '背景海賊団',
  ],
};

List<String> discoveryTermsFor(PrintingVariant variant) =>
    _discoveryTerms[variant.name] ?? const [];
