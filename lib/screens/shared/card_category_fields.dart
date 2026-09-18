import 'package:flutter/material.dart';

import '../../models/card_field_options.dart';
import '../../models/card_language.dart';
import '../../models/release_category.dart';

/// The "Card Details" section shared by every card create/edit form
/// (`AddManualScreen`, `NameTagFileScreen`, `EditCardScreen`): ID, Name,
/// Language, Rarity, and whichever of Kind/Color/Type apply to [category].
/// A card has no category of its own — it's whatever its release is (see
/// `ReleaseCategory`), so callers resolve `ReleaseCategory.others` for an
/// unsorted card.
class CardCategoryFields extends StatelessWidget {
  const CardCategoryFields({
    super.key,
    required this.category,
    required this.idController,
    required this.nameController,
    required this.language,
    required this.onLanguageChanged,
    required this.rarity,
    required this.onRarityChanged,
    this.kind,
    this.onKindChanged,
    this.color,
    this.onColorChanged,
    this.type,
    this.onTypeChanged,
  });

  final ReleaseCategory category;
  final TextEditingController idController;
  final TextEditingController nameController;
  final CardLanguage? language;
  final ValueChanged<CardLanguage?> onLanguageChanged;
  final String? rarity;
  final ValueChanged<String?> onRarityChanged;
  final String? kind;
  final ValueChanged<String?>? onKindChanged;
  final String? color;
  final ValueChanged<String?>? onColorChanged;
  final String? type;
  final ValueChanged<String?>? onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final rarityOptions = CardFieldOptions.rarity[category]!;
    final kindOptions = CardFieldOptions.kind[category];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: idController,
                decoration: const InputDecoration(labelText: 'ID'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<CardLanguage?>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final l in CardLanguage.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: onLanguageChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: rarityOptions.contains(rarity) ? rarity : null,
          decoration: const InputDecoration(labelText: 'Rarity'),
          items: [
            for (final r in rarityOptions) DropdownMenuItem(value: r, child: Text(r)),
          ],
          onChanged: onRarityChanged,
        ),
        if (kindOptions != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: kindOptions.contains(kind) ? kind : null,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              for (final k in kindOptions) DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: onKindChanged,
          ),
        ],
        if (category == ReleaseCategory.onePiece) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: CardFieldOptions.onePieceColor.contains(color)
                ? color
                : null,
            decoration: const InputDecoration(labelText: 'Color'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final c in CardFieldOptions.onePieceColor)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: onColorChanged,
          ),
        ],
        if (category == ReleaseCategory.pokemon) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: CardFieldOptions.pokemonType.contains(type)
                ? type
                : null,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final t in CardFieldOptions.pokemonType)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: onTypeChanged,
          ),
        ],
      ],
    );
  }
}
