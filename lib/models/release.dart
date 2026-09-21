import 'card_language.dart';
import 'release_category.dart';

class Release {
  final String id;
  final String name;
  final DateTime dateCreated;
  final String? coverPhotoPath;
  final bool coverPortrait;
  final int orderIndex;
  final String? officialSetCode;
  final int? totalCardsInSet;
  final ReleaseCategory category;
  final CardLanguage? language;
  final String? landscapeCoverPath;
  final String? portraitCoverPath;
  final bool isFavorite;

  const Release({
    required this.id,
    required this.name,
    required this.dateCreated,
    this.coverPhotoPath,
    this.coverPortrait = false,
    required this.orderIndex,
    this.officialSetCode,
    this.totalCardsInSet,
    this.category = ReleaseCategory.others,
    this.language,
    this.landscapeCoverPath,
    this.portraitCoverPath,
    this.isFavorite = false,
  });

  /// Landscape cover to display, falling back to the legacy single cover
  /// image for folders that predate separate landscape/portrait covers.
  String? get displayLandscapeCover => landscapeCoverPath ?? coverPhotoPath;

  /// Portrait cover to display, falling back to the legacy single cover
  /// image for folders that predate separate landscape/portrait covers.
  String? get displayPortraitCover => portraitCoverPath ?? coverPhotoPath;

  Release copyWith({
    String? name,
    String? coverPhotoPath,
    bool? coverPortrait,
    int? orderIndex,
    String? officialSetCode,
    int? totalCardsInSet,
    ReleaseCategory? category,
    CardLanguage? language,
    bool clearLanguage = false,
    String? landscapeCoverPath,
    bool clearLandscapeCover = false,
    String? portraitCoverPath,
    bool clearPortraitCover = false,
    bool? isFavorite,
  }) {
    return Release(
      id: id,
      name: name ?? this.name,
      dateCreated: dateCreated,
      coverPhotoPath: coverPhotoPath ?? this.coverPhotoPath,
      coverPortrait: coverPortrait ?? this.coverPortrait,
      orderIndex: orderIndex ?? this.orderIndex,
      officialSetCode: officialSetCode ?? this.officialSetCode,
      totalCardsInSet: totalCardsInSet ?? this.totalCardsInSet,
      category: category ?? this.category,
      language: clearLanguage ? null : (language ?? this.language),
      landscapeCoverPath: clearLandscapeCover
          ? null
          : (landscapeCoverPath ?? this.landscapeCoverPath),
      portraitCoverPath: clearPortraitCover
          ? null
          : (portraitCoverPath ?? this.portraitCoverPath),
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'dateCreated': dateCreated.toIso8601String(),
    'coverPhotoPath': coverPhotoPath,
    'coverPortrait': coverPortrait ? 1 : 0,
    'orderIndex': orderIndex,
    'officialSetCode': officialSetCode,
    'totalCardsInSet': totalCardsInSet,
    'category': category.label,
    'language': language?.label,
    'landscapeCoverPath': landscapeCoverPath,
    'portraitCoverPath': portraitCoverPath,
    'isFavorite': isFavorite ? 1 : 0,
  };

  factory Release.fromMap(Map<String, Object?> map) => Release(
    id: map['id'] as String,
    name: map['name'] as String,
    dateCreated: DateTime.parse(map['dateCreated'] as String),
    coverPhotoPath: map['coverPhotoPath'] as String?,
    coverPortrait: (map['coverPortrait'] as int? ?? 0) == 1,
    orderIndex: map['orderIndex'] as int,
    officialSetCode: map['officialSetCode'] as String?,
    totalCardsInSet: map['totalCardsInSet'] as int?,
    category: ReleaseCategory.fromLabel(map['category'] as String?),
    language: CardLanguage.fromLabel(map['language'] as String?),
    landscapeCoverPath: map['landscapeCoverPath'] as String?,
    portraitCoverPath: map['portraitCoverPath'] as String?,
    isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
  );
}
