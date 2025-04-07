import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:wheel_picker/wheel_picker.dart';

import '/utils/utils.dart';
import '/utils/route_observer.dart';
import '/utils/data.dart';
import '/utils/models.dart';
import 'deck_viewer.dart';
import 'deck_scanner.dart';
import 'download_screen.dart';
import 'image_processing_screen.dart';
import 'settings.dart';

class MyDecksOverview extends StatefulWidget {
  const MyDecksOverview({super.key});

  @override
  MyDecksOverviewState createState() => MyDecksOverviewState();
}

class MyDecksOverviewState extends State<MyDecksOverview> with RouteAware {
  late Future<List<Deck>> decksFuture;
  late Future<List<Set>> setsFuture;
  late Future<List<Cube>> cubesFuture;
  late Future buildFuture;
  late DeckStorage _deckStorage;
  final _expandableFabKey = GlobalKey<ExpandableFabState>();

  @override
  void initState() {
    super.initState();
    _deckStorage = DeckStorage();
    decksFuture = _deckStorage.getAllDecks();
    setsFuture = _deckStorage.getAllSets();
    cubesFuture = _deckStorage.getAllCubes();
    decksFuture.then((_) {
      setState(() {});
    });
    _deckStorage.getAllCards().then((cards) async {
      if (cards.isEmpty) {
        Navigator.of(context).push(
            MaterialPageRoute(
                builder: (context) => DownloadScreen()
            )
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  // Make sure decks are up-to-date when we return to page
  @override
  void didPopNext() {
    debugPrint("didPopNext() was fired");
    refreshDecks();
  }

  void refreshDecks() {
    setState(() {
      decksFuture = _deckStorage.getAllDecks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("My Decks"),
      ),
      floatingActionButtonLocation: ExpandableFab.location,
      floatingActionButton: ExpandableFab(
        key: _expandableFabKey,
        type: ExpandableFabType.fan,
        pos: ExpandableFabPos.center,
        fanAngle: 120,
        overlayStyle: ExpandableFabOverlayStyle(color: Colors.black87.withAlpha(0)),
        distance: 90,
        openButtonBuilder: FloatingActionButtonBuilder(
          size: 56,
          builder: (BuildContext context, void Function()? onPressed,
              Animation<double> progress) {
            return FloatingActionButton(
              heroTag: null,
              onPressed: null,
              shape: CircleBorder(),
              child: const Icon(Icons.add),
            );
          },
        ),
        closeButtonBuilder: FloatingActionButtonBuilder(
          size: 56,
          builder: (BuildContext context, void Function()? onPressed,
              Animation<double> progress) {
            return FloatingActionButton(
              mini: true,
              backgroundColor: Colors.grey,
              foregroundColor: Colors.black87,
              heroTag: null,
              onPressed: null,
              shape: CircleBorder(),
              splashColor: Colors.white38,
              child: const Icon(Icons.close),
            );
          },
        ),
        children: [
          FloatingActionButton(
            heroTag: null,
            shape: CircleBorder(),
            child: const Icon(Icons.image),
            onPressed: () async {
              final state = _expandableFabKey.currentState;
              if (state != null) {
                state.toggle();
              }
              final ImagePicker picker = ImagePicker();
              final XFile? image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                img.Image inputImage = img.decodeImage(File(image.path).readAsBytesSync())!;
                Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => deckImageProcessing(inputImage: inputImage)
                    )
                );
              }
            },
          ),
          FloatingActionButton(
            heroTag: null,
            shape: CircleBorder(),
            child: const Icon(Icons.camera),
            onPressed: () {
              final state = _expandableFabKey.currentState;
              if (state != null) {
                state.toggle();
              }
              Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => DeckScanner()
                  )
              );
            },
          ),
          FloatingActionButton(
            heroTag: null,
            shape: CircleBorder(),
            onPressed: null,
            child: const Icon(Icons.text_fields_outlined),
          )
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 65,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.sync_alt),
              onPressed: null
            ),
            Spacer(),
            IconButton(
                tooltip: "Settings Menu",
                icon: Icon(Icons.settings),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => Settings()
                    )
                )
            ),
          ]
        ),
      ),
      body: FutureBuilder(
        future: Future.wait([decksFuture, setsFuture, cubesFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
            return Center(child: CircularProgressIndicator());
          } else {
            // Getting state
            final decks = snapshot.data![0] as List<Deck>;
            final sets = snapshot.data![1] as List<Set>;
            final cubes = snapshot.data![2] as List<Cube>;

            if (decks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 20,
                  children: [
                    Spacer(flex: 4),
                    Text("No decks found", style: TextStyle(fontSize: 20)),
                    Spacer(flex: 3),
                    Text('Use the "+" button below to add a deck', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.white38)),
                    Spacer(flex: 3)
                  ]
                )
              );
            }

            // the map id is "${set_id/cube_id} $draft_id"
            Map<String, int> indexMap = {};
            List<List<Deck>> groupedDecks = [];
            // FIXME: Weird bug happening
            for (Deck deck in decks) {
              if ((deck.setId != null || deck.cubecobraId != null) && deck.draftId != null) {
                String key = "${deck.setId ?? deck.cubecobraId} ${deck.draftId}";
                if (indexMap.keys.contains(key)) {
                  groupedDecks[indexMap[key]!].add(deck);
                } else {
                  indexMap[key] = groupedDecks.length;
                  groupedDecks.add([deck]);
                }
              } else {
                groupedDecks.add([deck]);
              }
            }

            String decksYmd(List<Deck> decks) {
              String retVal = decks[0].ymd;
              for (Deck deck in decks) {
                if (retVal.compareTo(deck.ymd) < 0) {
                  retVal = deck.ymd;
                }
              }
              return retVal;
            }

            groupedDecks.sort((a, b) => decksYmd(a).compareTo(decksYmd(b)));

            return ListView.separated(
              itemCount: groupedDecks.length,
              separatorBuilder: (context, index) => Divider(indent: 20, endIndent: 20, color: Colors.white12),
              itemBuilder: (context, index) {
                if (groupedDecks[index].length == 1) {
                  return generateSlidableDeckTile(decks, sets, cubes, decks.indexOf(groupedDecks[index].first));
                } else {
                  String identifier = "";
                  if (groupedDecks[index][0].setId != null) {
                    identifier = sets.firstWhere((x) => x.code == groupedDecks[index][0].setId).name;
                  } else {
                    identifier = cubes.firstWhere((x) => x.cubecobraId == groupedDecks[index][0].cubecobraId).name;
                  }

                  return ExpansionTile(
                    title: Text("$identifier Draft #${groupedDecks[index][0].draftId}"),
                    subtitle: Text("${groupedDecks[index].length} decks\n${decksYmd(groupedDecks[index])}"),
                    children: groupedDecks[index].map((deck) => generateSlidableDeckTile(decks, sets, cubes, decks.indexOf(deck))).toList(),
                  );
                }
              },
            );
          }
        }
      )
    );
  }

  Widget generateSlidableDeckTile(List<Deck> decks, List<Set> sets, List<Cube> cubes, int index) {

    String subtitle = "";
    if (decks[index].winLoss != null) {
      subtitle = "${subtitle}W\L: ${decks[index].winLoss}\n";
    }
    if (decks[index].setId != null) {
      subtitle = "${subtitle}Set: ${sets.firstWhere((x) => x.code == decks[index].setId).name}\n";
    }
    if (decks[index].cubecobraId != null) {
      subtitle = "${subtitle}Cube: ${cubes.firstWhere((x) => x.cubecobraId == decks[index].cubecobraId).name}\n";
    }
    if (decks[index].draftId != null) {
      subtitle = "${subtitle}Draft ID: #${decks[index].draftId}\n";
    }
    subtitle = "$subtitle${decks[index].ymd}";

    return Slidable(
      startActionPane: ActionPane(
        extentRatio: 0.3,
        motion: BehindMotion(),
        children: [SlidableAction(
          label: "Edit",
          icon: Icons.edit_rounded,
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          onPressed: (_) {
            showDialog(
              context: context,
              builder: (_) => createEditDialog(index, decks, sets, cubes),
            );
          },
        )]
      ),
      endActionPane: ActionPane(
        extentRatio: 0.3,
        motion: ScrollMotion(),
        children: [SlidableAction(
          label: "Delete",
          icon: Icons.delete_rounded,
          backgroundColor: Colors.red,
          onPressed: (_) {
            showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text('Confirmation'),
                content: Text('Are you sure you want to delete this deck?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text("Cancel")
                  ),
                  TextButton(
                    onPressed: () {
                      _deckStorage.deleteDeck(decks[index].id);
                      Navigator.of(dialogContext).pop();
                    },
                    child: Text("Delete")
                  )
                ],
              ),
            );
          }
        )]
      ),
      child: ListTile(
        leading: deckColorsWidget(decks[index]),
        title: Text(
          decks[index].name != null ? "${decks[index].name}" : "Draft Deck ${index + 1}",
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.keyboard_arrow_right_rounded, size: 25),
        subtitle: Text(
          subtitle,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DeckViewer(deckId: decks[index].id)
        )),
      )
    );
  }

  Widget createEditDialog(int index, List<Deck> decks, List<Set> sets, List<Cube> cubes) {

    Deck deck = decks[index];
    String selectedDate = deck.ymd;
    final nameController = TextEditingController(text: deck.name);
    final draftIdController = TextEditingController();
    final winController = WheelPickerController(itemCount: 4, initialIndex: 4);
    final lossController = WheelPickerController(itemCount: 4, initialIndex: 4);
    final setCubeController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    String? currentCubeSetId = deck.cubecobraId ?? deck.setId;
    String draftType = deck.cubecobraId != null ? "cube" : "set";
    String? currentDraftId = deck.draftId != null ? deck.draftId.toString() : "";

    Widget createPaddedText(String text) {
      return Container(
        padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    return AlertDialog(
      title: Text('Edit Deck'),
      scrollable: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      content: StatefulBuilder(
        builder: (context, setState) {
          return Form(
            key: _formKey,
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
                    hintText: "Enter name here"
                  ),
                ),
                createPaddedText("Win - Loss"),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  // mainAxisSize: MainAxisSize.min,
                  children: [
                    generateWinLossPicker(winController),
                    Text("-", style: TextStyle(fontSize: 24)),
                    generateWinLossPicker(lossController),
                  ],
                ),
                SegmentedButton(
                  segments: [
                    ButtonSegment(
                      label: Text("Set"),
                      value: "set",
                      enabled: currentDraftId == ""
                    ),
                    ButtonSegment(
                      label: Text("Cube"),
                      value: "cube",
                      enabled: currentDraftId == ""
                    ),
                  ],
                  selected: {draftType},
                  onSelectionChanged: (newSelection) {
                    setState(() {
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
                  initialSelection: draftType == "set" ? decks[index].setId : decks[index].cubecobraId,
                  dropdownMenuEntries: generateDraftMenuItems(sets, cubes, draftType),
                  onSelected: (value) {
                    setState(() {
                      currentCubeSetId = value;
                    });
                  },
                  enabled: currentDraftId == "",
                ),
                createPaddedText("Draft ID"),
                DropdownMenu(
                  hintText: "Used for grouping",
                  enabled: currentCubeSetId != null,
                  controller: draftIdController,
                  initialSelection: decks[index].draftId.toString(),
                  dropdownMenuEntries: generateDraftIdMenuItems(sets, cubes, decks, index),
                  onSelected: (value) {
                    setState(() {
                      currentDraftId = value;
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
                            lastDate: DateTime(2100)
                        );
                        debugPrint(date.toString());
                        if (date != null) {
                          setState(() {
                            selectedDate = convertDatetimeToYMD(date);
                          });
                        }
                      },
                      child: Text(selectedDate)
                    )
                  ],
                )
              ],
            )
          );
        }
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Dismiss")
        ),
        TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Since this is an existing deck_id, it should overwrite
                // metadata in db.

                // Get largest int from corresponding decks in cube/set
                int? newDraftId;

                if (draftIdController.text == "Add new Draft ID") {
                  if (draftType == "set") {
                    List<int> draftIds = decks
                        .where((deck) => deck.setId == currentCubeSetId)
                        .where((deck) => deck.draftId != null)
                        .map((deck) => deck.draftId!)
                        .toList();
                    newDraftId = draftIds.isEmpty ? 1 : draftIds.reduce(max) + 1;
                  } else {
                    List<int> draftIds = decks
                        .where((deck) => deck.cubecobraId == currentCubeSetId)
                        .where((deck) => deck.draftId != null)
                        .map((deck) => deck.draftId!)
                        .toList();
                    newDraftId = draftIds.isEmpty ? 1 : draftIds.reduce(max) + 1;
                  }
                } else {
                  newDraftId = currentDraftId != null && currentDraftId != "" ? int.parse(currentDraftId!) : null;
                }

                final name = nameController.text;
                final String winLoss = "${3 - winController.selected}/${3 - lossController.selected}";
                final setId = draftType == "set" ? currentCubeSetId : null;
                final cubecobraId = draftType == "cube" ? currentCubeSetId : null;
                _deckStorage.insertDeck({
                  'id': deck.id,
                  'name': name.isEmpty ? null : name,
                  'win_loss': winLoss,
                  'set_id': setId,
                  'cubecobra_id': cubecobraId,
                  'draft_id': newDraftId,
                  'ymd': selectedDate});
                refreshDecks();
                Navigator.of(context).pop();
              }
            },
            child: Text("Save")
        )
      ],
    );
  }

  List<DropdownMenuEntry<String>> generateDraftMenuItems(List<Set> sets, List<Cube> cubes, String draftType) {
    if (draftType == "set") {
      return (sets
        ..sort((a, b) => (a.name.toString().compareTo(b.name.toString()))))
          .map((set) => DropdownMenuEntry(value: set.code, label: set.name)).toList();
    } else {
      return cubes.map((cube) => DropdownMenuEntry(value: cube.cubecobraId, label: cube.name)).toList();
    }
  }

  List<DropdownMenuEntry<String>> generateDraftIdMenuItems(
    List<Set> sets,
    List<Cube> cubes,
    List<Deck> decks,
    int index
  ) {
    List<String> draftIds = decks
        .where((deck) => deck.draftId != null)
        // limits draft_ids to ones of the current setId/cubeId. We want to keep draftIds isolated
        // within a set/cube.
        .where((deck) => (deck.setId == decks[index].setId && deck.setId != null) || (deck.cubecobraId == decks[index].cubecobraId && deck.cubecobraId != null))
        .map((deck) => deck.draftId.toString())
        .toList();
    draftIds = draftIds.toSet().toList();
    draftIds.sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    List<DropdownMenuEntry<String>> menuEntries = draftIds.map((id) => DropdownMenuEntry(value: id.toString(), label: "Draft #$id")).toList();
    menuEntries.add(DropdownMenuEntry(value: "add", label: "Add new Draft ID"));
    menuEntries.insert(0, DropdownMenuEntry(value: "", label: "None"));
    return menuEntries;
  }

  Widget generateWinLossPicker(WheelPickerController controller) {

    return SizedBox(
      height: 80,
      width: 50,
      child: WheelPicker(
        controller: controller,
        selectedIndexColor: Colors.white,
        looping: false,
        builder: (context, index) => Text((3 - index).toString(), style: TextStyle(fontSize: 24),),
        style: WheelPickerStyle(
            itemExtent: 25,
            diameterRatio: 1.2,
            surroundingOpacity: 0.3
        ),
      ),
    );
  }

  Widget deckColorsWidget (Deck deck) {
    int numColors = deck.colors.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: numColors*15),
      child: Row(
        children: [
          for (String color in deck.colors.split(""))
            SvgPicture.asset(
              "assets/svg_icons/$color.svg",
              height: 14,
            )
        ],
      )
    );
  }
}