class SubFolder {
  final String id;
  final String releaseId;
  final String name;
  final int orderIndex;

  const SubFolder({
    required this.id,
    required this.releaseId,
    required this.name,
    required this.orderIndex,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'releaseId': releaseId,
    'name': name,
    'orderIndex': orderIndex,
  };

  factory SubFolder.fromMap(Map<String, Object?> map) => SubFolder(
    id: map['id'] as String,
    releaseId: map['releaseId'] as String,
    name: map['name'] as String,
    orderIndex: map['orderIndex'] as int,
  );
}
