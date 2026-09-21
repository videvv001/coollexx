enum CaptureSessionStatus {
  active('ACTIVE'),
  committing('COMMITTING');

  final String label;
  const CaptureSessionStatus(this.label);

  static CaptureSessionStatus fromLabel(String label) {
    for (final s in CaptureSessionStatus.values) {
      if (s.label == label) return s;
    }
    return CaptureSessionStatus.active;
  }
}

/// A burst capture in progress. Created the moment the first photo of a
/// burst is persisted (see `CaptureSessionRepository.createSession`), so
/// the set of shots survives navigation, app backgrounding, and process
/// death even though nothing has been added to the collection yet.
///
/// There's no COMMITTED or DISCARDED status stored here: both are terminal
/// states represented by the session row simply no longer existing (its
/// items cascade-delete with it) — see `CaptureSessionRepository.commit`
/// and `.discard`. That keeps "is there something to recover" a single
/// cheap query (any row = yes) instead of a status filter that also has to
/// agree with a separate row-deletion policy.
class CaptureSession {
  final String id;
  final CaptureSessionStatus status;
  final String?
  targetReleaseId; // null = unsorted tray, same as TcgCard.releaseId
  final DateTime createdAt;
  final DateTime updatedAt;

  const CaptureSession({
    required this.id,
    required this.status,
    this.targetReleaseId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'status': status.label,
    'targetReleaseId': targetReleaseId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CaptureSession.fromMap(Map<String, Object?> map) => CaptureSession(
    id: map['id'] as String,
    status: CaptureSessionStatus.fromLabel(map['status'] as String),
    targetReleaseId: map['targetReleaseId'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
    updatedAt: DateTime.parse(map['updatedAt'] as String),
  );
}
