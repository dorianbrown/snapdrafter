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
      title: const Text('New Sets Available!'),
      content: Text(
        '$numberOfSets new Magic set(s) have been released '
        'since you last updated your card database.\n\n'
        'Would you like to update now to include these new sets?',
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
