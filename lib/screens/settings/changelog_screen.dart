import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '/utils/changelog_helper.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SnapDrafter Changelog")),
      body: FutureBuilder<List<ChangelogEntry>>(
        future: ChangelogHelper.loadChangelog(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load the changelog'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('No changelog entries yet'));
          }

          final theme = Theme.of(context);
          final markdownStyle = MarkdownStyleSheet.fromTheme(
            theme,
          ).copyWith(p: theme.textTheme.bodyMedium);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              for (final entry in entries) ...[
                if (entry.date != null)
                  Text(
                    entry.date!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  entry.version,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                MarkdownBody(
                  data: entry.body,
                  styleSheet: markdownStyle,
                  paddingBuilders: {'hr': ChangelogHrPaddingBuilder()},
                ),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}
