import 'package:flutter/material.dart';

import '../../models/release_category.dart';

/// Asks which game a scanned card belongs to, when that can't already be
/// told from a bound release — OCR's heuristics are per-game (see
/// `card_text_scan.dart`), so without this the app would be guessing where
/// on the card to even look. Returns null if dismissed, which callers treat
/// the same as `ReleaseCategory.others` (no autofill).
Future<ReleaseCategory?> pickOcrCategory(BuildContext context) {
  return showDialog<ReleaseCategory>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('What kind of card is this?'),
      children: [
        for (final c in ReleaseCategory.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, c),
            child: Text(c.label),
          ),
      ],
    ),
  );
}
