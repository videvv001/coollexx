import 'package:flutter/material.dart';

import '../../models/value_entry.dart';
import '../../utils/formatting.dart';

/// The whole spec for this input: two fields, date and value. Nothing else.
class AddValueSheet extends StatefulWidget {
  const AddValueSheet({super.key, this.lastAmount, this.editing});

  final double? lastAmount;
  final ValueEntry? editing;

  @override
  State<AddValueSheet> createState() => _AddValueSheetState();
}

class _AddValueSheetState extends State<AddValueSheet> {
  late DateTime _date = widget.editing?.date ?? DateTime.now();
  late final _amountController = TextEditingController(
    text: widget.editing != null
        ? widget.editing!.amount.toStringAsFixed(2)
        : widget.lastAmount != null
        ? widget.lastAmount!.toStringAsFixed(2)
        : '',
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a value', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(formatLongDate(_date)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: widget.editing == null,
            decoration: const InputDecoration(
              prefixText: '\$ ',
              hintText: 'Value',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Values are yours — typed in, never fetched. Enter one whenever '
            'you check a price.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(_amountController.text.trim());
              if (amount == null) return;
              Navigator.pop(context, (date: _date, amount: amount));
            },
            child: const Text('Save entry'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
