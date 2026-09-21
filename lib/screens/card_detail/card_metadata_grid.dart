import 'package:flutter/material.dart';

import 'card_metadata_fields.dart';

/// Renders a category's metadata fields as a compact 2-column grid (see
/// `card_metadata_fields.dart` for how the field list is chosen).
class CardMetadataGrid extends StatelessWidget {
  const CardMetadataGrid({super.key, required this.fields});

  final List<MetadataField> fields;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 3.4,
      children: [
        for (final field in fields)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                field.label,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(field.value, style: textTheme.titleMedium),
            ],
          ),
      ],
    );
  }
}
