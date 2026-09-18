enum ReleaseCategory {
  pokemon('Pokémon'),
  onePiece('One Piece'),
  others('Others');

  final String label;
  const ReleaseCategory(this.label);

  static ReleaseCategory fromLabel(String? label) {
    for (final c in ReleaseCategory.values) {
      if (c.label == label) return c;
    }
    return ReleaseCategory.others;
  }
}
