import '../../models/release.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';

/// One label/value pair in the card-detail metadata grid.
class MetadataField {
  const MetadataField(this.label, this.value);

  final String label;
  final String value;
}

typedef _FieldBuilder = List<MetadataField> Function(TcgCard card, Release? release);

const _dash = '—';

String _releaseLanguage(TcgCard card, Release? release) =>
    '${release?.name ?? _dash} / ${card.language?.label ?? _dash}';

List<MetadataField> _pokemonFields(TcgCard card, Release? release) {
  final number = card.number;
  final total = release?.totalCardsInSet;
  final id = number == null || number.isEmpty
      ? _dash
      : (total != null ? '#$number/$total' : '#$number');
  return [
    MetadataField('ID', id),
    MetadataField('RELEASE / LANGUAGE', _releaseLanguage(card, release)),
    MetadataField('KIND', card.kind ?? _dash),
    MetadataField('RARITY / TYPE', '${card.rarity ?? _dash} / ${card.type ?? _dash}'),
    MetadataField('CONDITION', card.condition?.label ?? _dash),
  ];
}

List<MetadataField> _onePieceFields(TcgCard card, Release? release) => [
  MetadataField('ID', card.number ?? _dash),
  MetadataField('RELEASE / LANGUAGE', _releaseLanguage(card, release)),
  MetadataField('KIND', card.kind ?? _dash),
  MetadataField('COLOR', card.color ?? _dash),
  MetadataField('RARITY', card.rarity ?? _dash),
  MetadataField('CONDITION', card.condition?.label ?? _dash),
];

List<MetadataField> _oneColumnRarityFields(TcgCard card, Release? release) => [
  MetadataField('ID', card.number ?? _dash),
  MetadataField('RELEASE / LANGUAGE', _releaseLanguage(card, release)),
  MetadataField('RARITY', card.rarity ?? _dash),
  MetadataField('CONDITION', card.condition?.label ?? _dash),
];

/// Category → metadata template. Adding a new category (Yu-Gi-Oh!, Magic,
/// Sports, ...) is a new map entry here, not a new branch scattered through
/// the UI.
const _fieldBuilders = <ReleaseCategory, _FieldBuilder>{
  ReleaseCategory.pokemon: _pokemonFields,
  ReleaseCategory.onePiece: _onePieceFields,
  ReleaseCategory.others: _oneColumnRarityFields,
};

List<MetadataField> cardMetadataFields(
  ReleaseCategory category,
  TcgCard card,
  Release? release,
) => _fieldBuilders[category]!(card, release);
