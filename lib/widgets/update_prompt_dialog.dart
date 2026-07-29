import 'package:flutter/material.dart';

class UpdatePromptDialog extends StatelessWidget {
  final List<Map<String, String>> sets;
  final VoidCallback onUpdateNow;
  final VoidCallback onRemindLater;
  final bool isInitialDownload;

  const UpdatePromptDialog({
    super.key,
    this.sets = const [],
    required this.onUpdateNow,
    required this.onRemindLater,
    this.isInitialDownload = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = isInitialDownload
        ? 'Scryfall Data Missing'
        : 'New Set${(sets.length > 1) ? "s" : ""} Available!';

    final content = isInitialDownload
        ? 'Your card database is empty, and SnapDrafter needs this card data to function.\n'
            '\n'
            'Would you like to download it now?'
        : () {
            var mappedSets = sets
                .map((s) => ' \u2022 ${s['name']} (${s['code']!.toUpperCase()})')
                .toList();

            var setNames = '';
            if (mappedSets.length > 5) {
              setNames = '${mappedSets.sublist(0, 5).join('\n')}\n \u2022 ...';
            } else {
              setNames = mappedSets.join('\n');
            }

            return '${sets.length} additional Magic set${(sets.length > 1) ? "s" : ""} '
                '${(sets.length > 1) ? "are" : "is"} available on Scryfall for download:\n'
                '\n'
                '$setNames\n'
                '\n'
                'Would you like to update your card database now?';
          }();

    return AlertDialog(
      title: Text(title),
      content: Text(content),
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
