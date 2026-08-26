import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '/utils/changelog_helper.dart';

class ChangelogDialog extends StatelessWidget {
  final List<ChangelogEntry> entries;

  const ChangelogDialog({
    super.key,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
      h1Padding: const EdgeInsets.all(3),
      h2: theme.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
      h3: theme.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
      p: theme.textTheme.bodyMedium,
    );

    return AlertDialog(
      title: const Text("SnapDrafter Changelog"),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: MarkdownBody(
            data: entries.map((e) => e.markdown).join('\n\n'),
            styleSheet: markdownStyle,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
