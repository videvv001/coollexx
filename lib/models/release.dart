class Release {
  final String id;
  final String name;
  final DateTime dateCreated;
  final String? coverPhotoPath;
  final int orderIndex;
  final String? officialSetCode;
  final int? totalCardsInSet;

  const Release({
    required this.id,
    required this.name,
    required this.dateCreated,
    this.coverPhotoPath,
    required this.orderIndex,
    this.officialSetCode,
    this.totalCardsInSet,
  });

  Release copyWith({
    String? name,
    String? coverPhotoPath,
    int? orderIndex,
    String? officialSetCode,
    int? totalCardsInSet,
  }) {
    return Release(
      id: id,
      name: name ?? this.name,
      dateCreated: dateCreated,
      coverPhotoPath: coverPhotoPath ?? this.coverPhotoPath,
      orderIndex: orderIndex ?? this.orderIndex,
      officialSetCode: officialSetCode ?? this.officialSetCode,
      totalCardsInSet: totalCardsInSet ?? this.totalCardsInSet,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'dateCreated': dateCreated.toIso8601String(),
    'coverPhotoPath': coverPhotoPath,
    'orderIndex': orderIndex,
    'officialSetCode': officialSetCode,
    'totalCardsInSet': totalCardsInSet,
  };

  factory Release.fromMap(Map<String, Object?> map) => Release(
    id: map['id'] as String,
    name: map['name'] as String,
    dateCreated: DateTime.parse(map['dateCreated'] as String),
    coverPhotoPath: map['coverPhotoPath'] as String?,
    orderIndex: map['orderIndex'] as int,
    officialSetCode: map['officialSetCode'] as String?,
    totalCardsInSet: map['totalCardsInSet'] as int?,
  );
}
