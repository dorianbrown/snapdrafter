import 'package:flutter/material.dart';

class UpdatePromptDialog extends StatelessWidget {
  final int numberOfSets;
  final VoidCallback onUpdateNow;
  final VoidCallback onRemindLater;
  
  const UpdatePromptDialog({
    super.key,
    required this.numberOfSets,
    required this.onUpdateNow,
    required this.onRemindLater,
  });
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New Set${(numberOfSets > 1) ? "s" : ""} Available!'),
      content: Text(
        '$numberOfSets additional Magic set${(numberOfSets > 1) ? "s" : ""} '
        '${(numberOfSets > 1) ? "are" : "is"} available on Scryfall for download.\n\n'
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
