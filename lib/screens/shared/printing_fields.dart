import 'package:flutter/material.dart';

import '../../models/printing_variant.dart';

/// Which physical printing a card is: family, specific name and an artwork
/// note. A manual override — normally the scan fills this in — for correcting
/// a wrong reading or entering a printing the scan couldn't tell. Leaving it
/// "Unknown" is fine and means the card is not priced yet; it never means
/// "base".
class PrintingFields extends StatefulWidget {
  const PrintingFields({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PrintingVariant value;
  final ValueChanged<PrintingVariant> onChanged;

  @override
  State<PrintingFields> createState() => _PrintingFieldsState();
}

class _PrintingFieldsState extends State<PrintingFields> {
  late final _name = TextEditingController(text: widget.value.name);
  late final _artwork = TextEditingController(text: widget.value.artwork);
  late VariantFamily _family = widget.value.family;

  @override
  void dispose() {
    _name.dispose();
    _artwork.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(
    PrintingVariant(
      family: _family,
      name: normalizeVariantName(_name.text),
      artwork: _artwork.text.trim().isEmpty ? null : _artwork.text.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final named =
        _family != VariantFamily.unknown && _family != VariantFamily.base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<VariantFamily>(
          initialValue: _family,
          decoration: const InputDecoration(labelText: 'Printing'),
          items: [
            for (final f in VariantFamily.values)
              DropdownMenuItem(value: f, child: Text(f.label)),
          ],
          onChanged: (f) {
            setState(() => _family = f ?? VariantFamily.unknown);
            _emit();
          },
        ),
        if (named) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Printing name (optional)',
              hintText: 'e.g. Red Manga Rare',
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if (_family != VariantFamily.unknown) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _artwork,
            decoration: const InputDecoration(
              labelText: 'Artwork (optional)',
              hintText: 'What the artwork shows',
            ),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}
