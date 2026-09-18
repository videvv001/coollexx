import 'card_condition.dart';

/// A single collected card. Named `TcgCard` to avoid colliding with
/// Flutter's own `Card` widget.
class TcgCard {
  final String id;
  final String? name;
  final String? number;
  final String? rarity;
  final CardCondition? condition;
  final int copies;
  final String? releaseId; // null = unsorted
  final String? subFolderId; // null = in the release but no sub-folder
  final List<String> photoPaths; // first = thumbnail
  final double? pricePaid;
  final DateTime? datePaid;
  final bool forTrade;
  final bool onWishlist;
  final String? notes;
  final DateTime createdAt;

  const TcgCard({
    required this.id,
    this.name,
    this.number,
    this.rarity,
    this.condition,
    this.copies = 1,
    this.releaseId,
    this.subFolderId,
    this.photoPaths = const [],
    this.pricePaid,
    this.datePaid,
    this.forTrade = false,
    this.onWishlist = false,
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
    CardCondition? condition,
    bool clearCondition = false,
    int? copies,
    String? releaseId,
    bool clearRelease = false,
    String? subFolderId,
    bool clearSubFolder = false,
    List<String>? photoPaths,
    double? pricePaid,
    DateTime? datePaid,
    bool? forTrade,
    bool? onWishlist,
    String? notes,
  }) {
    return TcgCard(
      id: id,
      name: name ?? this.name,
      number: number ?? this.number,
      rarity: rarity ?? this.rarity,
      condition: clearCondition ? null : (condition ?? this.condition),
      copies: copies ?? this.copies,
      releaseId: clearRelease ? null : (releaseId ?? this.releaseId),
      subFolderId: clearSubFolder ? null : (subFolderId ?? this.subFolderId),
      photoPaths: photoPaths ?? this.photoPaths,
      pricePaid: pricePaid ?? this.pricePaid,
      datePaid: datePaid ?? this.datePaid,
      forTrade: forTrade ?? this.forTrade,
      onWishlist: onWishlist ?? this.onWishlist,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'number': number,
    'rarity': rarity,
    'condition': condition?.label,
    'copies': copies,
    'releaseId': releaseId,
    'subFolderId': subFolderId,
    'photoPaths': photoPaths.join(''),
    'pricePaid': pricePaid,
    'datePaid': datePaid?.toIso8601String(),
    'forTrade': forTrade ? 1 : 0,
    'onWishlist': onWishlist ? 1 : 0,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TcgCard.fromMap(Map<String, Object?> map) => TcgCard(
    id: map['id'] as String,
    name: map['name'] as String?,
    number: map['number'] as String?,
    rarity: map['rarity'] as String?,
    condition: CardCondition.fromLabel(map['condition'] as String?),
    copies: map['copies'] as int? ?? 1,
    releaseId: map['releaseId'] as String?,
    subFolderId: map['subFolderId'] as String?,
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
    notes: map['notes'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
