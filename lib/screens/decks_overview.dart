import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:wheel_picker/wheel_picker.dart';
import 'package:collection/collection.dart';

import '/utils/utils.dart';
import '/utils/route_observer.dart';
import '/utils/data.dart';
import '/utils/models.dart';
import '/widgets/deck_tile.dart';
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
  Filter? currentFilter;

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
            onPressed: () => showTextDeckCreator(),
            child: const Icon(Icons.text_fields_outlined),
          )
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 65,
        child: Row(
          children: [
            IconButton(
              icon: Icon(currentFilter != null 
                ? Icons.filter_alt_off 
                : Icons.filter_alt),
              onPressed: () {
                if (currentFilter != null) {
                  setState(() => currentFilter = null);
                } else {
                  showDialog<Filter>(
                    context: context,
                    builder: (context) => createFilterDialog(),
                  ).then((filter) {
                    if (filter != null) {
                      setState(() => currentFilter = filter);
                    }
                  });
                }
              }
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

            List<Deck> filteredDecks = currentFilter != null
              ? decks.where((deck) => currentFilter!.matchesDeck(deck)).toList()
              : decks;
            filteredDecks.sort((a, b) => b.ymd.compareTo(a.ymd));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentFilter != null) Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  child: createFilterChips(currentFilter!, sets, cubes),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredDecks.length,
                    separatorBuilder: (context, index) => Divider(indent: 20, endIndent: 20, color: Colors.white12),
                    itemBuilder: (context, index) {
                      return generateSlidableDeckTile(filteredDecks, sets, cubes, index);
                    },
                  )
                )
              ],
            );
          }
        }
      )
    );
  }

  void showTextDeckCreator() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Create Deck"),
        content: TextFormField(
          expands: true,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: null,
          controller: controller,
          decoration: InputDecoration(
            hintText: "1 Mox Jet\n1 Black Lotus\n1 ...",
            hintStyle: TextStyle(color: Colors.white54)
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Discard")
          ),
          TextButton(
              onPressed: () async {
                List<Card> allCards = await _deckStorage.getAllCards();
                List<Card> deckList = [];

                List<String> text = controller.text.split("\n");
                final regex = RegExp(r'^(\d)\s(.+)$');
                for (String name in text) {
                  var regexMatch = regex.allMatches(name);
                  int count = int.parse(regexMatch.first[1]!);
                  String cardName = regexMatch.first[2]!;
                  Card? matchedCard = allCards.firstWhereOrNull((card) => card.name == cardName);
                  if (matchedCard == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Card not found: '$name'")));
                    return;
                  }
                  for (int i = 0; i < count; i++) {
                    deckList.add(matchedCard);
                  }
                }

                _deckStorage.saveNewDeck(DateTime.now(), deckList).then((_) {
                  Navigator.of(context).pop();
                });
              },
              child: const Text("Save")
          )
        ],
      )
    );
  }

  Widget generateSlidableDeckTile(List<Deck> decks, List<Set> sets, List<Cube> cubes, int index) {
    return DeckTile(
      deck: decks[index],
      sets: sets,
      cubes: cubes,
      onEdit: () => showDialog(
        context: context,
        builder: (_) => createEditDialog(index, decks, sets, cubes),
      ),
      onDelete: () => _confirmDeleteDeck(decks[index].id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeckViewer(deckId: decks[index].id),
        ),
      ),
    );
  }

  void _confirmDeleteDeck(int deckId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmation'),
        content: const Text('Are you sure you want to delete this deck?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              _deckStorage.deleteDeck(deckId);
              Navigator.of(dialogContext).pop();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Widget createFilterDialog() {
    DateTimeRange? dateRange;
    String? selectedSetId;
    String? selectedCubeId;
    String draftType = "set";
    RangeValues _winRange = const RangeValues(0, 3);

    return AlertDialog(
      title: Text("Filter Decks"),
      scrollable: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      content: StatefulBuilder(
        builder: (context, setState) {
          return FutureBuilder(
            future: Future.wait([decksFuture, setsFuture, cubesFuture]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return CircularProgressIndicator();

              final decksData = snapshot.data![0] as List<Deck>;
              final setsData = snapshot.data![1] as List<Set>;
              final cubesData = snapshot.data![2] as List<Cube>;

              final availableSets = setsData
                  .where((set) => decksData.any((deck) => deck.setId == set.code))
                  .toList();
              final availableCubes = cubesData
                  .where((cube) => decksData.any((deck) => deck.cubecobraId == cube.cubecobraId))
                  .toList();

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Date Range"),
                  OutlinedButton(
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDateRange: dateRange,
                      );
                      if (range != null) {
                        setState(() => dateRange = range);
                      }
                    },
                    child: Text(dateRange != null 
                      ? "${convertDatetimeToYMD(dateRange!.start)} - ${convertDatetimeToYMD(dateRange!.end)}"
                      : "Choose Date Range"
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text("Wins Range: ${_winRange.start.round()} - ${_winRange.end.round()}"),
                  ),
                  RangeSlider(
                    values: _winRange,
                    min: 0,
                    max: 3,
                    divisions: 3,
                    labels: RangeLabels(
                      _winRange.start.round().toString(),
                      _winRange.end.round().toString(),
                    ),
                    onChanged: (RangeValues values) {
                      setState(() => _winRange = values);
                    },
                  ),
                  SegmentedButton(
                    segments: [
                      ButtonSegment(label: Text("Set"), value: "set"),
                      ButtonSegment(label: Text("Cube"), value: "cube"),
                    ],
                    selected: {draftType},
                    onSelectionChanged: (newSelection) {
                      setState(() {
                        draftType = newSelection.first;
                        selectedSetId = null;
                        selectedCubeId = null;
                      });
                    },
                  ),
                  DropdownMenu(
                    hintText: "Select $draftType",
                    dropdownMenuEntries: draftType == "set"
                      ? availableSets.map((set) => 
                          DropdownMenuEntry(value: set.code, label: set.name))
                          .toList()
                      : availableCubes.map((cube) =>
                          DropdownMenuEntry(value: cube.cubecobraId, label: cube.name))
                          .toList(),
                    onSelected: (value) {
                      setState(() {
                        if (draftType == "set") {
                          selectedSetId = value;
                          selectedCubeId = null;
                        } else {
                          selectedCubeId = value;
                          selectedSetId = null;
                        }
                      });
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Clear"),
        ),
        TextButton(
          onPressed: () {
            final filter = Filter(
              startDate: dateRange?.start,
              endDate: dateRange?.end,
              setId: selectedSetId,
              cubecobraId: selectedCubeId,
              minWins: _winRange.start.round(),
              maxWins: _winRange.end.round(),
            );
            Navigator.of(context).pop(filter);
          },
          child: Text("Apply"),
        ),
      ],
    );
  }

  Widget createEditDialog(int index, List<Deck> decks, List<Set> sets, List<Cube> cubes) {

    Deck deck = decks[index];
    String selectedDate = deck.ymd;
    final nameController = TextEditingController(text: deck.name);
    final winController = WheelPickerController(itemCount: 4, initialIndex: 4);
    final lossController = WheelPickerController(itemCount: 4, initialIndex: 4);
    final setCubeController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    String? currentCubeSetId = deck.cubecobraId ?? deck.setId;
    String draftType = deck.cubecobraId != null ? "cube" : "set";

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
                Container(
                  padding: EdgeInsets.symmetric(vertical: 7, horizontal: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // mainAxisSize: MainAxisSize.min,
                    children: [
                      generateWinLossPicker(winController),
                      Text("-", style: TextStyle(fontSize: 24)),
                      generateWinLossPicker(lossController),
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


  Widget createFilterChips(Filter filter, List<Set> sets, List<Cube> cubes) {
    return Wrap(
      spacing: 5,
      runSpacing: -5,
      children: [
        if (filter.setId != null)
          Chip(
            label: Text("Set: ${sets.firstWhere((set) => set.code == filter.setId).name}"),
            onDeleted: () => setState(() {
              currentFilter = filter.clearSetId();
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          ),
        if (filter.cubecobraId != null)
          Chip(
            label: Text("Cube: ${cubes.firstWhere((cube) => cube.cubecobraId == filter.cubecobraId).name}"),
            onDeleted: () => setState(() {
              currentFilter = filter.clearCubecobraId();
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          ),
        if (filter.startDate != null || filter.endDate != null)
          Chip(
            label: Text(formatDateRange(filter.startDate, filter.endDate)),
            onDeleted: () => setState(() {
              currentFilter = filter.clearDateRange();
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          ),
        if (filter.minWins != 0 || filter.maxWins != 3)
          Chip(
            label: Text("Wins: ${filter.minWins == filter.maxWins ? filter.minWins : '${filter.minWins}-${filter.maxWins}'}"),
            onDeleted: () => setState(() {
              currentFilter = filter.clearWinRange();
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          ),
        Chip(
          label: Text("Clear Filters"),
          onDeleted: () => setState(() => currentFilter = null),
          labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
          padding: EdgeInsets.all(6),
        ),
      ],
    );
  }
}
