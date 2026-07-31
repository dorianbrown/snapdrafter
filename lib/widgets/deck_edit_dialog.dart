import 'package:flutter/material.dart' hide Card;
import 'package:wheel_picker/wheel_picker.dart';

import '/data/models/deck.dart';
import '/data/models/set.dart';
import '/data/models/cube.dart';
import '/data/models/deck_upsert.dart';
import '/data/repositories/deck_repository.dart';
import '/utils/utils.dart';

Widget _generateWinLossPicker(WheelPickerController controller, BuildContext context) {
  return SizedBox(
    height: 80,
    width: 50,
    child: WheelPicker(
      controller: controller,
      selectedIndexColor: Theme.of(context).hintColor,
      looping: false,
      builder: (context, index) => Text(
        (3 - index).toString(),
        style: TextStyle(fontSize: 24),
      ),
      style: WheelPickerStyle(
          itemExtent: 25, diameterRatio: 1.2, surroundingOpacity: 0.3),
    ),
  );
}

List<DropdownMenuEntry<String>> _generateDraftMenuItems(
    List<Set> sets, List<Cube> cubes, String draftType) {
  if (draftType == "set") {
    return (sets..sort((a, b) => (b.releasedAt.compareTo(a.releasedAt))))
        .map((set) => DropdownMenuEntry(value: set.code, label: set.name))
        .toList();
  } else {
    return cubes
        .map((cube) =>
            DropdownMenuEntry(value: cube.cubecobraId, label: cube.name))
        .toList();
  }
}

Future<void> showDeckEditDialog(
  BuildContext context, {
  required Deck deck,
  required List<Set> sets,
  required List<Cube> cubes,
  required List<String> allTags,
  required DeckRepository deckRepository,
  required VoidCallback onSaved,
}) {
  String selectedDate = deck.ymd;
  final nameController = TextEditingController(text: deck.name);
  final winController =
      WheelPickerController(itemCount: 4, initialIndex: 3 - (deck.wins ?? 0));
  final lossController = WheelPickerController(
      itemCount: 4, initialIndex: 3 - (deck.losses ?? 0));
  final drawController = WheelPickerController(
      itemCount: 4, initialIndex: 3 - (deck.draws ?? 0));
  final setCubeController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? currentCubeSetId = deck.cubecobraId ?? deck.setId;
  String draftType = deck.cubecobraId != null ? "cube" : "set";
  List<String> deckTags = List.from(deck.tags);
  final tagController = TextEditingController();

  Widget createPaddedText(String text) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Edit Deck'),
      scrollable: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      content: StatefulBuilder(builder: (context, setDialogState) {
        return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                createPaddedText("Deck Name"),
                TextFormField(
                  controller: nameController,
                  style: TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter name here"),
                ),
                createPaddedText("Win - Loss - Draw"),
                Container(
                  padding: EdgeInsets.symmetric(vertical: 7, horizontal: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _generateWinLossPicker(winController, context),
                      Text("-", style: TextStyle(fontSize: 24)),
                      _generateWinLossPicker(lossController, context),
                      Text("-", style: TextStyle(fontSize: 24)),
                      _generateWinLossPicker(drawController, context),
                    ],
                  ),
                ),
                SegmentedButton(
                  segments: [
                    ButtonSegment(
                      label: Text("Set"),
                      value: "set",
                    ),
                    ButtonSegment(
                      label: Text("Cube"),
                      value: "cube",
                    ),
                  ],
                  selected: {draftType},
                  onSelectionChanged: (newSelection) {
                    setDialogState(() {
                      draftType = newSelection.first;
                      currentCubeSetId = switch (draftType) {
                        "set" => deck.setId,
                        "cube" => deck.cubecobraId,
                        _ => null
                      };
                      if (currentCubeSetId == null) {
                        setCubeController.text = "";
                      }
                    });
                  },
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                    ),
                  ),
                ),
                DropdownMenu(
                  hintText: "Select $draftType",
                  controller: setCubeController,
                  initialSelection: draftType == "set"
                      ? deck.setId
                      : deck.cubecobraId,
                  dropdownMenuEntries:
                      _generateDraftMenuItems(sets, cubes, draftType),
                  onSelected: (value) {
                    setDialogState(() {
                      currentCubeSetId = value;
                    });
                  },
                ),
                createPaddedText("Date"),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                        onPressed: () async {
                          DateTime? date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(selectedDate),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100));
                          if (date != null) {
                            setDialogState(() {
                              selectedDate = convertDatetimeToYMD(date);
                            });
                          }
                        },
                        child: Text(selectedDate))
                  ],
                ),
                createPaddedText("Tags"),
                if (allTags.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text("Available Tags:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Wrap(
                    spacing: 6,
                    children: allTags.map((tag) {
                      final isSelected = deckTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        selected: isSelected,
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              deckTags.add(tag);
                            } else {
                              deckTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: tagController,
                        decoration: InputDecoration(
                          labelText: 'Add new tag',
                          border: OutlineInputBorder(),
                          hintText: 'Enter custom tag',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add),
                      tooltip: "Add tag",
                      onPressed: () {
                        final tag = tagController.text.trim();
                        if (tag.isNotEmpty && !deckTags.contains(tag)) {
                          setDialogState(() {
                            deckTags.add(tag);
                            allTags.add(tag);
                            tagController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ));
      }),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text("Dismiss")),
        TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final Map<String, Object?> updates = {};

                final name = nameController.text;
                if (name != deck.name) {
                  updates['name'] = name.isEmpty ? null : name;
                }

                final int newWins = 3 - winController.selected;
                final int newLosses = 3 - lossController.selected;
                final int newDraws = 3 - drawController.selected;
                if (newWins != deck.wins ||
                    newLosses != deck.losses ||
                    newDraws != deck.draws) {
                  updates['wins'] = newWins;
                  updates['losses'] = newLosses;
                  updates['draws'] = newDraws;
                }

                final setId = draftType == "set" ? currentCubeSetId : null;
                if (setId != deck.setId) {
                  updates['set_id'] = setId;
                }

                final cubecobraId =
                    draftType == "cube" ? currentCubeSetId : null;
                if (cubecobraId != deck.cubecobraId) {
                  updates['cubecobra_id'] = cubecobraId;
                }

                if (selectedDate != deck.ymd) {
                  updates['ymd'] = selectedDate;
                }

                if (updates.isNotEmpty) {
                  await deckRepository.updateDeck(DeckUpsert(
                    id: deck.id,
                    name: updates['name'] as String?,
                    wins: updates.containsKey('wins')
                        ? updates['wins'] as int?
                        : deck.wins,
                    losses: updates.containsKey('losses')
                        ? updates['losses'] as int?
                        : deck.losses,
                    draws: updates.containsKey('draws')
                        ? updates['draws'] as int?
                        : deck.draws,
                    setId: updates['set_id'] as String?,
                    cubecobraId: updates['cubecobra_id'] as String?,
                    ymd: updates['ymd'] as String?,
                    cards: deck.cards,
                    sideboard: deck.sideboard,
                  ));
                }

                final currentTags = deck.tags;
                for (final tag in currentTags) {
                  if (!deckTags.contains(tag)) {
                    await deckRepository.removeTagFromDeck(deck.id, tag);
                  }
                }
                for (final tag in deckTags) {
                  if (!currentTags.contains(tag)) {
                    await deckRepository.addTagToDeck(deck.id, tag);
                  }
                }

                onSaved();
                Navigator.of(context).pop();
              }
            },
            child: Text("Save"))
      ],
    ),
  );
}
