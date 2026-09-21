/// One persisted photo within a `CaptureSession`. `path` already points at
/// a file `PhotoStore` saved permanently at capture time — nothing here is
/// a copy or a second location, this row is purely the "this file belongs
/// to an in-progress burst" bookkeeping that survives process death.
///
/// `committedCardId` is set the moment this item's `TcgCard` is created
/// during commit — checked first on every commit attempt, which is what
/// makes retrying an interrupted commit safe to repeat without creating a
/// duplicate collection entry.
class CaptureItem {
  final String id;
  final String sessionId;
  final String path;
  final int sequence;
  final DateTime capturedAt;
  final String? committedCardId;

  const CaptureItem({
    required this.id,
    required this.sessionId,
    required this.path,
    required this.sequence,
    required this.capturedAt,
    this.committedCardId,
  });

  CaptureItem copyWith({String? path}) => CaptureItem(
    id: id,
    sessionId: sessionId,
    path: path ?? this.path,
    sequence: sequence,
    capturedAt: capturedAt,
    committedCardId: committedCardId,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'sessionId': sessionId,
    'path': path,
    'sequence': sequence,
    'capturedAt': capturedAt.toIso8601String(),
    'committedCardId': committedCardId,
  };

  factory CaptureItem.fromMap(Map<String, Object?> map) => CaptureItem(
    id: map['id'] as String,
    sessionId: map['sessionId'] as String,
    path: map['path'] as String,
    sequence: map['sequence'] as int,
    capturedAt: DateTime.parse(map['capturedAt'] as String),
    committedCardId: map['committedCardId'] as String?,
  );
}
