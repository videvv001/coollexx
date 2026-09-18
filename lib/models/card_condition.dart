enum CardCondition {
  nm('NM'),
  ex('EX'),
  gd('GD'),
  pl('PL');

  final String label;
  const CardCondition(this.label);

  static CardCondition? fromLabel(String? label) {
    if (label == null) return null;
    for (final c in CardCondition.values) {
      if (c.label == label) return c;
    }
    return null;
  }
}
