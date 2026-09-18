enum CardLanguage {
  jp('JP'),
  eng('ENG'),
  cn('CN'),
  kr('KR');

  final String label;
  const CardLanguage(this.label);

  static CardLanguage? fromLabel(String? label) {
    if (label == null) return null;
    for (final l in CardLanguage.values) {
      if (l.label == label) return l;
    }
    return null;
  }
}
