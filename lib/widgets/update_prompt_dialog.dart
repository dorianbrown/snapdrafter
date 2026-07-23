import 'package:flutter/material.dart';

class UpdatePromptDialog extends StatelessWidget {
  final List<Map<String, String>> sets;
  final VoidCallback onUpdateNow;
  final VoidCallback onRemindLater;
  
  const UpdatePromptDialog({
    super.key,
    required this.sets,
    required this.onUpdateNow,
    required this.onRemindLater,
  });
  
  @override
  Widget build(BuildContext context) {
    final setNames = sets
        .map((s) => ' \u2022 ${s['name']} (${s['code']!.toUpperCase()})')
        .join('\n');

    return AlertDialog(
      title: Text('New Set${(sets.length > 1) ? "s" : ""} Available!'),
      content: Text(
        '${sets.length} additional Magic set${(sets.length > 1) ? "s" : ""} '
        '${(sets.length > 1) ? "are" : "is"} available on Scryfall for download:\n'
        '\n'
        '$setNames\n'
        '\n'
        'Would you like to update your card database now?',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onRemindLater();
          },
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onUpdateNow();
          },
          child: const Text('Update Now'),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceEvenly,
    );
  }
}
