import 'package:flutter/material.dart' hide Card;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

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
          )
        ]
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
          )
        ]
      ),
      child: ListTile(
        leading: _buildDeckColors(deck.colors),
        title: Text(
          deck.name ?? "Draft Deck",
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 25),
        subtitle: Text(_buildSubtitle()),
        onTap: onTap,
      )
    );
  }

  String _buildSubtitle() {
    final buffer = StringBuffer();
    if (deck.winLoss != null) buffer.writeln("W/L: ${deck.winLoss}");
    if (deck.setId != null) buffer.writeln("Set: ${_getSetName()}");
    if (deck.cubecobraId != null) buffer.writeln("Cube: ${_getCubeName()}");
    buffer.write(deck.ymd);
    return buffer.toString();
  }

  String _getSetName() {
    return sets.firstWhere((set) => set.code == deck.setId).name;
  }

  String _getCubeName() {
    return cubes.firstWhere((cube) => cube.cubecobraId == deck.cubecobraId).name;
  }

  Widget _buildDeckColors(String colors) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: colors.length * 15),
      child: Row(
        children: [
          for (String color in colors.split(""))
            SvgPicture.asset(
              "assets/svg_icons/$color.svg",
              height: 14,
            )
        ],
      )
    );
  }
}
