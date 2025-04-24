import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/models.dart';

class DeckTile extends StatefulWidget {
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
  State<DeckTile> createState() => _DeckTileState();
}

class _DeckTileState extends State<DeckTile> {
  @override
  Widget build(BuildContext context) {
    if (widget.showFirstDeckHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstDeckTutorial(context);
        widget.onFirstDeckViewed();
      });
    }

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
            onPressed: (_) => widget.onEdit(),
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
            onPressed: (_) => widget.onDelete(),
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
        onTap: widget.onTap,
      )
    );
  }

  void _showFirstDeckTutorial(BuildContext context) {
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
    widget.onFirstDeckViewed(); // Mark as seen after showing toast
  }

  String _buildSubtitle() {
    String subtitle = "";
    if (widget.deck.winLoss != null) {
      subtitle = "${subtitle}W/L: ${widget.deck.winLoss}\n";
    }
    if (widget.deck.setId != null) {
      subtitle = "${subtitle}Set: ${widget.sets.firstWhere((x) => x.code == widget.deck.setId).name}\n";
    }
    if (widget.deck.cubecobraId != null) {
      subtitle = "${subtitle}Cube: ${widget.cubes.firstWhere((x) => x.cubecobraId == widget.deck.cubecobraId).name}\n";
    }
    return "$subtitle${widget.deck.ymd}";
  }

  Widget _buildColorIcons() {
    int numColors = widget.deck.colors.length;
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
