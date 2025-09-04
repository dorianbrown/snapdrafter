import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:wheel_picker/wheel_picker.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/models/filter.dart';
import '/widgets/deck_tile.dart';
import 'deck_viewer.dart';
import 'deck_scanner.dart';
import 'settings/download_screen.dart';
import 'image_processing_screen.dart';
import 'settings.dart';

import '/data/models/deck.dart';
import '/data/models/card.dart';
import '/data/models/cube.dart';
import '/data/models/set.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/cube_repository.dart';
import '/data/repositories/card_repository.dart';

class MyDecksOverview extends StatefulWidget {
  const MyDecksOverview({super.key});

  @override
  MyDecksOverviewState createState() => MyDecksOverviewState();
}

class MyDecksOverviewState extends State<MyDecksOverview> with RouteAware {
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();
  late Future<List<Deck>> decksFuture;
  late Future<List<Set>> setsFuture;
  late Future<List<Cube>> cubesFuture;
  late DeckRepository deckRepository;
  late SetRepository setRepository;
  late CubeRepository cubeRepository;
  late CardRepository cardRepository;
  late Future buildFuture;
  final _expandableFabKey = GlobalKey<ExpandableFabState>();
  Filter? currentFilter;
  bool _hasSeenOverviewTutorial = false;
  List<String> allTags = [];
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    deckRepository = DeckRepository();
    setRepository = SetRepository();
    cubeRepository = CubeRepository();
    decksFuture = deckRepository.getAllDecks();
    setsFuture = setRepository.getAllSets();
    cubesFuture = cubeRepository.getAllCubes();

    _changeNotifier.addListener(_refreshIfNeeded);
    decksFuture.then((_) {
      setState(() {});
    });
    cardRepository = CardRepository();
    cardRepository.getAllCards();
    _loadFirstDeckStatus();
    _loadTags();

    WidgetsBinding.instance.addPostFrameCallback((_) => launchWelcomeDialog());

  }

  Future<void> _loadTags() async {
    final tags = await deckRepository.getAllTags();
    setState(() {
      allTags = tags;
    });
  }

  Future<void> _loadFirstDeckStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSeenOverviewTutorial = prefs.getBool("overview_tutorial_seen") ?? false;
  }

  Future<void> _markFirstDeckSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("overview_tutorial_seen", true);
    _hasSeenOverviewTutorial = true;
  }

  void _refreshIfNeeded() {
    if (_changeNotifier.needsRefresh) {
      refreshDecks();
      _loadTags();
      _changeNotifier.clearRefresh();
    }
  }

  void refreshDecks() async {
    setState(() {
      setsFuture = setRepository.getAllSets();
      cubesFuture = cubeRepository.getAllCubes();
      decksFuture = deckRepository.getAllDecks();
    });
  }

  @override
  void dispose() {
    _changeNotifier.removeListener(_refreshIfNeeded);
    super.dispose();
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
                await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => deckImageProcessing(filePath: image.path)
                    )
                );
              }
            },
          ),
          FloatingActionButton(
            heroTag: null,
            shape: CircleBorder(),
            child: const Icon(Icons.camera),
            onPressed: () async {
              final state = _expandableFabKey.currentState;
              if (state != null) {
                state.toggle();
              }
              await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => DeckScanner()
                  )
              );
            },
          ),
          FloatingActionButton(
            heroTag: null,
            shape: CircleBorder(),
            onPressed: () async {
              showTextDeckCreator();
            },
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
          Widget widget;
          if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
            widget = Center(child: CircularProgressIndicator());
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
                    Text('Use the "+" button below to add a deck', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)),
                    Spacer(flex: 3)
                  ]
                )
              );
            }

            List<Deck> filteredDecks = currentFilter != null
              ? decks.where((deck) => currentFilter!.matchesDeck(deck)).toList()
              : decks;
            filteredDecks.sort((a, b) => b.ymd.compareTo(a.ymd));

            widget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentFilter != null) Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  child: createFilterChips(currentFilter!, sets, cubes),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredDecks.length,
                    separatorBuilder: (context, index) => Divider(indent: 20, endIndent: 20),
                    itemBuilder: (context, index) {
                      return generateSlidableDeckTile(filteredDecks, sets, cubes, index);
                    },
                  )
                )
              ],
            );
          }
          // return widget;
          return AnimatedSwitcher(
            duration: Duration(milliseconds: 500),
            child: widget
          );
        }
      )
    );
  }

  void showTextDeckCreator() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => ScaffoldMessenger(
        child: Builder(
          builder: (builderContext) => Scaffold(
            backgroundColor: Colors.transparent,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: AlertDialog(
                title: Text("Create Deck"),
                content: TextFormField(
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  minLines: null,
                  controller: controller,
                  decoration: InputDecoration(
                      hintText: "1 Mox Jet\n1 Black Lotus\n1 ...",
                      hintStyle: TextStyle(color: Theme.of(context).hintColor)
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Discard")
                  ),
                  TextButton(
                      onPressed: () async {
                        List<Card> allCards = await cardRepository.getAllCards();
                        List<Card> deckList = [];

                        List<String> text = controller.text.split("\n");
                        final regex = RegExp(r'^(\d+)\s(.+)$');
                        for (String name in text) {
                          var regexMatch = regex.allMatches(name);
                          try {
                            int count = int.parse(regexMatch.first[1]!);
                            String cardName = regexMatch.first[2]!;
                            Card? matchedCard = allCards.firstWhereOrNull(
                                    (card) {
                                  if (card.name.contains(" // ")) {
                                    return card.name.contains(" // ")
                                        ? card.name.split(" // ").any((name) => name.toLowerCase() == cardName.toLowerCase())
                                        : card.name.toLowerCase() == cardName.toLowerCase();
                                  }
                                  else {
                                    return card.name.toLowerCase() == cardName.toLowerCase();
                                  }
                                }
                            );
                            if (matchedCard == null) {
                              ScaffoldMessenger.of(builderContext).showSnackBar(SnackBar(content: Text("Card not found: '$cardName'")));
                              return;
                            }
                            for (int i = 0; i < count; i++) {
                              deckList.add(matchedCard);
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(builderContext).showSnackBar(SnackBar(content: Text("Incorrect format for '$name'")));
                            return;
                          }
                        }

                        deckRepository.saveNewDeck(DateTime.now(), deckList).then((_) {
                          refreshDecks();
                          Navigator.of(context).pop();
                        });
                      },
                      child: const Text("Save")
                  )
                ],
              ),
            )
          )
        )
      )
    );
  }

  Widget generateSlidableDeckTile(List<Deck> decks, List<Set> sets, List<Cube> cubes, int index) {
    return DeckTile(
      deck: decks[index],
      sets: sets,
      cubes: cubes,
      showFirstDeckHint: !_hasSeenOverviewTutorial && index == 0,
      onFirstDeckViewed: _markFirstDeckSeen,
      onEdit: () => showDialog(
        context: context,
        builder: (_) => createEditDialog(index, decks, sets, cubes),
      ),
      onDelete: () => _confirmDeleteDeck(decks[index].id),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DeckViewer(deck: decks[index]),
          ),
        );
      },
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
            onPressed: () async {
              await deckRepository.deleteDeck(deckId);
              Navigator.of(dialogContext).pop();
              refreshDecks();
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
    RangeValues winRange = const RangeValues(0, 3);
    List<String> selectedTags = currentFilter?.tags ?? [];
    List<String> includedColors = currentFilter?.includedColors ?? [];
    List<String> excludedColors = currentFilter?.excludedColors ?? [];

    return AlertDialog(
      title: Text("Filter Decks"),
      scrollable: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      content: StatefulBuilder(
        builder: (context, setDialogState) {
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
                  SizedBox(
                    height: 5,
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDateRange: dateRange,
                      );
                      if (range != null) {
                        setDialogState(() => dateRange = range);
                      }
                    },
                    child: Text(dateRange != null 
                      ? "${convertDatetimeToYMD(dateRange!.start)} - ${convertDatetimeToYMD(dateRange!.end)}"
                      : "Choose Date Range"
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text("Wins Range: ${winRange.start.round()} - ${winRange.end.round()}"),
                  ),
                  RangeSlider(
                    values: winRange,
                    min: 0,
                    max: 3,
                    divisions: 3,
                    labels: RangeLabels(
                      winRange.start.round().toString(),
                      winRange.end.round().toString(),
                    ),
                    onChanged: (RangeValues values) {
                      setDialogState(() => winRange = values);
                    },
                  ),
                  SegmentedButton(
                    segments: [
                      ButtonSegment(label: Text("Set"), value: "set"),
                      ButtonSegment(label: Text("Cube"), value: "cube"),
                    ],
                    selected: {draftType},
                    onSelectionChanged: (newSelection) {
                      setDialogState(() {
                        draftType = newSelection.first;
                        selectedSetId = null;
                        selectedCubeId = null;
                      });
                    },
                  ),
                  SizedBox(
                    height: 5
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
                      setDialogState(() {
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
                  Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 10),
                    child: Text("Colors"),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final color in ["W", "U", "B", "R", "G"])
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              // Cycle through states: neutral -> included -> excluded -> neutral
                              if (includedColors.contains(color)) {
                                includedColors.remove(color);
                                excludedColors.add(color);
                              } else if (excludedColors.contains(color)) {
                                excludedColors.remove(color);
                              } else {
                                includedColors.add(color);
                              }
                            });
                          },
                          onLongPress: () {
                            setDialogState(() {
                              // Long press to clear the state
                              includedColors.remove(color);
                              excludedColors.remove(color);
                            });
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              border: includedColors.contains(color)
                                  ? Border.all(color: Colors.blue, width: 2)
                                  : excludedColors.contains(color)
                                      ? Border.all(color: Colors.red, width: 2)
                                      : null,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SvgPicture.asset(
                              "assets/svg_icons/$color.svg",
                              colorFilter: (includedColors.contains(color) || 
                                           excludedColors.contains(color))
                                  ? null
                                  : ColorFilter.mode(
                                      Colors.grey.withAlpha(150),
                                      BlendMode.dstOut,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 10),
                    child: Text("Tags"),
                  ),
                  Wrap(
                    spacing: 6,
                    children: allTags.map((tag) {
                      final isSelected = selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        selected: isSelected,
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              selectedTags.add(tag);
                            } else {
                              selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
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
              minWins: winRange.start.round(),
              maxWins: winRange.end.round(),
              tags: selectedTags,
              includedColors: includedColors,
              excludedColors: excludedColors,
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
    // Determining Win/Loss for initial wheel picker values
    int initialWins = 0;
    int initialLosses = 0;
    if (deck.winLoss != null) {
      initialWins = int.parse(deck.winLoss!.split("/")[0]);
      initialLosses = int.parse(deck.winLoss!.split("/")[1]);
    }
    final winController = WheelPickerController(itemCount: 4, initialIndex: 3 - initialWins);
    final lossController = WheelPickerController(itemCount: 4, initialIndex: 3 - initialLosses);
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

    return AlertDialog(
      title: Text('Edit Deck'),
      scrollable: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      content: StatefulBuilder(
        builder: (context, setDialogState) {
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
                  initialSelection: draftType == "set" ? decks[index].setId : decks[index].cubecobraId,
                  dropdownMenuEntries: generateDraftMenuItems(sets, cubes, draftType),
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
                            lastDate: DateTime(2100)
                        );
                        if (date != null) {
                          setDialogState(() {
                            selectedDate = convertDatetimeToYMD(date);
                          });
                        }
                      },
                      child: Text(selectedDate)
                    )
                  ],
                ),
                createPaddedText("Tags"),
                // Show available tags as toggleable chips
                if (allTags.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text("Available Tags:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                // Add new tag section
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
            )
          );
        }
      ),
      actions: [
        TextButton(
            onPressed: () {
              _loadTags();
              Navigator.of(context).pop();
            },
            child: Text("Dismiss")
        ),
        TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                // Build update map with only changed fields
                final Map<String, Object?> updates = {};
                
                final name = nameController.text;
                if (name != deck.name) {
                  updates['name'] = name.isEmpty ? null : name;
                }
                
                final String winLoss = "${3 - winController.selected}/${3 - lossController.selected}";
                if (winLoss != deck.winLoss) {
                  updates['win_loss'] = winLoss;
                }
                
                final setId = draftType == "set" ? currentCubeSetId : null;
                if (setId != deck.setId) {
                  updates['set_id'] = setId;
                }
                
                final cubecobraId = draftType == "cube" ? currentCubeSetId : null;
                if (cubecobraId != deck.cubecobraId) {
                  updates['cubecobra_id'] = cubecobraId;
                }
                
                if (selectedDate != deck.ymd) {
                  updates['ymd'] = selectedDate;
                }
                
                // Only update if there are changes
                if (updates.isNotEmpty) {
                  await deckRepository.updateDeck(deck.id, updates);
                }
                
                // Update tags
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
                
                refreshDecks();
                _loadTags(); // Reload tags to include any newly added ones
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
        ..sort((a, b) => (b.releasedAt.compareTo(a.releasedAt))))
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
        selectedIndexColor: Theme.of(context).hintColor,
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
        if (filter.includedColors.isNotEmpty)
          ...filter.includedColors.map((color) => Chip(
            label: Text(""),
            avatar: SvgPicture.asset("assets/svg_icons/$color.svg", height: 18,),
            side: BorderSide(color: Colors.blue.shade200),
            onDeleted: () => setState(() {
              final newIncludedColors = List<String>.from(filter.includedColors)..remove(color);
              currentFilter = filter.copyWith(includedColors: newIncludedColors);
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          )).toList(),
        if (filter.excludedColors.isNotEmpty)
          ...filter.excludedColors.map((color) => Chip(
            label: Text(""),
            avatar: SvgPicture.asset("assets/svg_icons/$color.svg", height: 18,),
            side: BorderSide(color: Colors.red.shade200),
            onDeleted: () => setState(() {
              final newExcludedColors = List<String>.from(filter.excludedColors)..remove(color);
              currentFilter = filter.copyWith(excludedColors: newExcludedColors);
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          )).toList(),
        if (filter.tags.isNotEmpty)
          ...filter.tags.map((tag) => Chip(
            label: Text("Tag: $tag"),
            onDeleted: () => setState(() {
              final newTags = List<String>.from(filter.tags)..remove(tag);
              currentFilter = filter.copyWith(tags: newTags);
              if (currentFilter!.isEmpty()) {
                currentFilter = null;
              }
            }),
            labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            padding: EdgeInsets.all(6),
          )).toList(),
        ActionChip(
          label: Text("Clear Filters"),
          onPressed: () => setState(() => currentFilter = null),
          labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
          padding: EdgeInsets.all(6),
          avatar: Icon(Icons.filter_alt),
        ),
      ],
    );
  }

  Future launchWelcomeDialog() async {

    final prefs = await SharedPreferences.getInstance();
    bool hasSeenWelcomePopup = prefs.getBool("welcome_popup_seen") ?? false;

    if (!hasSeenWelcomePopup) {

      prefs.setBool("welcome_popup_seen", true);

      TextStyle titleStyle = TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold
      );
      double paragraphBreak = 4;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              SizedBox(height: paragraphBreak,),
              Text("Welcome to SnapDrafter!", style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold
              )),
              SizedBox(height: paragraphBreak,),
              Text("Getting Started", style: titleStyle,),
              Text("I try to make the interface as intuitive as possible, but "
                  "if can't figure something out, you can find some additional "
                  "information in 'Settings > Help'."),
              SizedBox(height: paragraphBreak,),
              Text("Feedback", style: titleStyle,),
              Text("In case you find a bug, have ideas for how things could "
                "be improved, or features that are missing, I'd love to hear "
                  "your feedback."),
              Text("Clicking 'Settings > Feedback' will give you an invite to "
                  "the SnapDrafter Discord server."),
              SizedBox(height: paragraphBreak,),
              Text("Support", style: titleStyle,),
              Text("My aim is to keep SnapDrafter free, ad-free, and available"
                  " to as many cube-lovers as possible. Donations make that "
                  "possible."),
              Text("You can find links in 'Settings > Donations'.")
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (context) => DownloadScreen()
                  ));
                },
                child: Text("Close")
            ),
          ],
        ),
      );
    }
  }

}
