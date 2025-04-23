import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/models.dart';

class DeckTile extends StatelessWidget {
  final Deck deck;
  final List<Set> sets;
  final List<Cube> cubes;
  final bool showFirstDeckHint;
  final VoidCallback onFirstDeckViewed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const DeckTile({
    super.key,
    required this.deck,
    required this.sets,
    required this.cubes,
    required this.showFirstDeckHint,
    required this.onFirstDeckViewed,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (showFirstDeckHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstDeckTooltip(context);
        onFirstDeckViewed();
      });
    }

    String subtitle = _buildSubtitle();

    return Stack(
      children: [
        Slidable(
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
        ),
        if (showFirstDeckHint)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.star, size: 16, color: Colors.white),
            ),
          ),
      ],
    );
  }

  void _showFirstDeckTooltip(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('This is your first deck! Tap any deck to view its contents'),
        duration: Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
    onFirstDeckViewed(); // Mark as seen after showing toast
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
