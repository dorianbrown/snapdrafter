import 'package:flutter/material.dart' hide Card;
import 'package:collection/collection.dart';

import '../../data/models/card.dart';
import '../../utils/constants.dart';

const _headerStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline,
);

void showDecklistPreviewSheet(
  BuildContext context, {
  required String playerName,
  required List<Card> mainboard,
  required List<Card> sideboard,
  VoidCallback? onSave,
}) {
  final sortedMain = [...mainboard]
    ..sort((a, b) => a.manaValue.compareTo(b.manaValue));
  final sortedSide = [...sideboard]
    ..sort((a, b) => a.manaValue.compareTo(b.manaValue));

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "$playerName's Decklist",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                ..._buildGroupedCards(sortedMain),
                if (sortedSide.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Sideboard (${sortedSide.length})', style: _headerStyle),
                  const SizedBox(height: 8),
                  ..._buildCardRows(sortedSide),
                ],
                if (onSave != null) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        onSave();
                        Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Save to Collection'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

List<Widget> _buildGroupedCards(List<Card> cards) {
  final widgets = <Widget>[];

  for (final attribute in typeOrder) {
    final grouped = cards
        .where((card) => _cardTypeMatches(card.type, attribute))
        .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1);

    if (grouped.isEmpty) continue;

    final total = grouped.entries.fold<int>(0, (s, e) => s + e.value);
    widgets.add(Text('$attribute ($total)', style: _headerStyle));
    widgets.add(const SizedBox(height: 4));

    for (final entry in grouped.entries) {
      widgets.add(_cardRow(entry.key, entry.value));
    }

    widgets.add(const SizedBox(height: 12));
  }

  return widgets;
}

List<Widget> _buildCardRows(List<Card> cards) {
  final grouped = cards.groupFoldBy(
    (item) => item,
    (int? sum, item) => (sum ?? 0) + 1,
  );

  return grouped.entries
      .map((entry) => _cardRow(entry.key, entry.value))
      .toList();
}

Widget _cardRow(Card card, int count) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      spacing: 8,
      children: [
        Expanded(
          child: Text(
            (count > 1) ? '$count x ${card.title}' : card.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        card.createManaCost(),
      ],
    ),
  );
}

bool _cardTypeMatches(String? type, String attribute) {
  if (type == null) return false;
  return type.contains(attribute);
}
