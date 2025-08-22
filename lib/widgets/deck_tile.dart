import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '/data/models/deck.dart';
import '/data/models/set.dart';
import '/data/models/cube.dart';

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

class _DeckTileState extends State<DeckTile> with SingleTickerProviderStateMixin {

  late SlidableController slidableController;

  @override
  void dispose() {
    slidableController.dispose();
    super.dispose();
  }

  void initState() {
    slidableController = SlidableController(this);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {

    // If the tutorial hasn't been shown yet, show it and mark in preferences.
    if (widget.showFirstDeckHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _showFirstDeckTutorial();
        widget.onFirstDeckViewed();
      });
    }

    Widget subtitle = _buildSubtitle();

    return Slidable(
      controller: slidableController,
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
          widget.deck.name != null ? widget.deck.name! : "Draft Deck",
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.keyboard_arrow_right_rounded, size: 25),
        subtitle: subtitle,
        onTap: widget.onTap,
      )
    );
  }

  // In order to explain slidability, we programmatically show both sides on first deck
  Future<void> _showFirstDeckTutorial() async {
    Curve _curve = Easing.emphasizedDecelerate;
    Future.delayed(Duration(milliseconds: 500)).then((_) async {
      await slidableController.openEndActionPane(duration: Duration(seconds: 1), curve: _curve);
    }).then((_) async {
      await slidableController.close(duration: Duration(seconds: 1), curve: _curve);
    }).then((_) async {
      await slidableController.openStartActionPane(duration: Duration(seconds: 1), curve: _curve);
    });
    widget.onFirstDeckViewed(); // Mark as seen after showing toast
  }

  Widget _buildSubtitle() {
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

    List<Widget> tagChips = widget.deck.tags.map((tag) {
      return Chip(
        label: Text(tag, style: TextStyle(fontSize: 12),),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$subtitle${widget.deck.ymd}"),
        if (tagChips.isNotEmpty)
          SizedBox(height: 4),
        Wrap(children: tagChips, spacing: 5, runSpacing: 5,),
      ],
    );
  }

  Widget _buildColorIcons() {
    int numColors = widget.deck.colors.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: numColors * 15),
      child: Row(
        children: [
          for (String color in widget.deck.colors.split(""))
            SvgPicture.asset(
              "assets/svg_icons/$color.svg",
              height: 14,
            ),
        ],
      ),
    );
  }
}
