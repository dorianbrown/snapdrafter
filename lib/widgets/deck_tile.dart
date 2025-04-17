import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/models.dart';

class DeckTile extends StatelessWidget {
  final Deck deck;
  final List<Set> sets;
  final List<Cube> cubes;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const DeckTile({
    super.key,
    required this.deck,
    required this.sets,
    required this.cubes,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String subtitle = _buildSubtitle();

    return Slidable(
      startActionPane: ActionPane(
        extentRatio: 0.3,
        motion: const BehindMotion(),
        children: [
          SlidableAction(
            label: "Edit",
            icon: Icons.edit_rounded,
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            onPressed: (_) => onEdit(),
          ),
        ],
      ),
      endActionPane: ActionPane(
        extentRatio: 0.3,
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            label: "Delete",
            icon: Icons.delete_rounded,
            backgroundColor: Colors.red,
            onPressed: (_) => onDelete(),
          ),
        ],
      ),
      child: ListTile(
        leading: _buildColorIcons(),
        title: Text(
          deck.name != null ? deck.name! : "Draft Deck",
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 25),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }

  String _buildSubtitle() {
    String subtitle = "";
    if (deck.winLoss != null) {
      subtitle = "${subtitle}W/L: ${deck.winLoss}\n";
    }
    if (deck.setId != null) {
      subtitle = "${subtitle}Set: ${sets.firstWhere((x) => x.code == deck.setId).name}\n";
    }
    if (deck.cubecobraId != null) {
      subtitle = "${subtitle}Cube: ${cubes.firstWhere((x) => x.cubecobraId == deck.cubecobraId).name}\n";
    }
    return "$subtitle${deck.ymd}";
  }

  Widget _buildColorIcons() {
    int numColors = deck.colors.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: numColors * 15),
      child: Row(
        children: [
          for (String color in deck.colors.split(""))
            SvgPicture.asset(
              "assets/svg_icons/$color.svg",
              height: 14,
            ),
        ],
      ),
    );
  }
}
