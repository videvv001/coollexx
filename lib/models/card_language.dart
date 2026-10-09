enum CardLanguage {
  jp('JP', 'Japanese'),
  eng('ENG', 'English'),
  cn('CN', 'Chinese'),
  kr('KR', 'Korean');

  final String label;

  /// The printed language as pricing and recognition name it.
  final String printed;
  const CardLanguage(this.label, this.printed);

  static CardLanguage? fromPrinted(String? printed) {
    final p = printed?.trim().toLowerCase();
    for (final l in CardLanguage.values) {
      if (l.printed.toLowerCase() == p) return l;
    }
    return null;
  }

  static CardLanguage? fromLabel(String? label) {
    if (label == null) return null;
    for (final l in CardLanguage.values) {
      if (l.label == label) return l;
    }
    return null;
  }
}
