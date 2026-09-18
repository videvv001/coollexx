import 'card_condition.dart';
import 'card_language.dart';

/// A single collected card. Named `TcgCard` to avoid colliding with
/// Flutter's own `Card` widget.
class TcgCard {
  final String id;
  final String? name;
  final String? number;
  final String? rarity;
  final CardLanguage? language;
  final String? kind; // One Piece / Pokémon only
  final String? color; // One Piece only
  final String? type; // Pokémon only
  final CardCondition? condition;
  final int copies;
  final String? releaseId; // null = unsorted
  final List<String> photoPaths; // first = thumbnail
  final double? pricePaid;
  final DateTime? datePaid;
  final bool forTrade;
  final bool onWishlist;
  final bool isFavorite;
  final String? notes;
  final DateTime createdAt;

  const TcgCard({
    required this.id,
    this.name,
    this.number,
    this.rarity,
    this.language,
    this.kind,
    this.color,
    this.type,
    this.condition,
    this.copies = 1,
    this.releaseId,
    this.photoPaths = const [],
    this.pricePaid,
    this.datePaid,
    this.forTrade = false,
    this.onWishlist = false,
    this.isFavorite = false,
    this.notes,
    required this.createdAt,
  });

  bool get isUntitled => name == null || name!.trim().isEmpty;
  bool get hasPhoto => photoPaths.isNotEmpty;
  String? get thumbnailPath => photoPaths.isNotEmpty ? photoPaths.first : null;

  TcgCard copyWith({
    String? name,
    String? number,
    String? rarity,
    CardLanguage? language,
    bool clearLanguage = false,
    String? kind,
    bool clearKind = false,
    String? color,
    bool clearColor = false,
    String? type,
    bool clearType = false,
    CardCondition? condition,
    bool clearCondition = false,
    int? copies,
    String? releaseId,
    bool clearRelease = false,
    List<String>? photoPaths,
    double? pricePaid,
    DateTime? datePaid,
    bool? forTrade,
    bool? onWishlist,
    bool? isFavorite,
    String? notes,
  }) {
    return TcgCard(
      id: id,
      name: name ?? this.name,
      number: number ?? this.number,
      rarity: rarity ?? this.rarity,
      language: clearLanguage ? null : (language ?? this.language),
      kind: clearKind ? null : (kind ?? this.kind),
      color: clearColor ? null : (color ?? this.color),
      type: clearType ? null : (type ?? this.type),
      condition: clearCondition ? null : (condition ?? this.condition),
      copies: copies ?? this.copies,
      releaseId: clearRelease ? null : (releaseId ?? this.releaseId),
      photoPaths: photoPaths ?? this.photoPaths,
      pricePaid: pricePaid ?? this.pricePaid,
      datePaid: datePaid ?? this.datePaid,
      forTrade: forTrade ?? this.forTrade,
      onWishlist: onWishlist ?? this.onWishlist,
      isFavorite: isFavorite ?? this.isFavorite,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'number': number,
    'rarity': rarity,
    'language': language?.label,
    'kind': kind,
    'color': color,
    'type': type,
    'condition': condition?.label,
    'copies': copies,
    'releaseId': releaseId,
    'photoPaths': photoPaths.join(''),
    'pricePaid': pricePaid,
    'datePaid': datePaid?.toIso8601String(),
    'forTrade': forTrade ? 1 : 0,
    'onWishlist': onWishlist ? 1 : 0,
    'isFavorite': isFavorite ? 1 : 0,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TcgCard.fromMap(Map<String, Object?> map) => TcgCard(
    id: map['id'] as String,
    name: map['name'] as String?,
    number: map['number'] as String?,
    rarity: map['rarity'] as String?,
    language: CardLanguage.fromLabel(map['language'] as String?),
    kind: map['kind'] as String?,
    color: map['color'] as String?,
    type: map['type'] as String?,
    condition: CardCondition.fromLabel(map['condition'] as String?),
    copies: map['copies'] as int? ?? 1,
    releaseId: map['releaseId'] as String?,
    photoPaths: ((map['photoPaths'] as String?) ?? '')
        .split('')
        .where((s) => s.isNotEmpty)
        .toList(),
    pricePaid: (map['pricePaid'] as num?)?.toDouble(),
    datePaid: map['datePaid'] == null
        ? null
        : DateTime.parse(map['datePaid'] as String),
    forTrade: (map['forTrade'] as int? ?? 0) == 1,
    onWishlist: (map['onWishlist'] as int? ?? 0) == 1,
    isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
    notes: map['notes'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
