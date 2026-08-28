import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/deck_text_editor.dart';
import '../widgets/deck_edit_dialog.dart';
import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/models/filter.dart';
import '/widgets/deck_tile.dart';
import 'deck_viewer.dart';
import 'deck_scanner.dart';
import 'image_processing_screen.dart';
import 'settings.dart';
import 'settings/backup.dart';
import 'draft/draft_lobby.dart';

import '/data/models/deck.dart';
import '/data/models/cube.dart';
import '/data/models/set.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/cube_repository.dart';
import '/data/repositories/card_repository.dart';
import '/data/database/database_helper.dart';

class MyDecksOverview extends StatefulWidget {
  const MyDecksOverview({super.key});

  @override
  MyDecksOverviewState createState() => MyDecksOverviewState();
}

class MyDecksOverviewState extends State<MyDecksOverview> {
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();
  late DeckRepository deckRepository;
  late SetRepository setRepository;
  late CubeRepository cubeRepository;
  late CardRepository cardRepository;
  final _expandableFabKey = GlobalKey<ExpandableFabState>();
  Filter? currentFilter;
  bool _hasSeenOverviewTutorial = false;
  List<String> allTags = [];
  List<Deck> _decks = [];
  List<Set> _sets = [];
  List<Cube> _cubes = [];
  bool _isLoading = true;
  int _refreshGen = 0;

  @override
  void initState() {
    super.initState();
    deckRepository = DeckRepository();
    setRepository = SetRepository();
    cubeRepository = CubeRepository();
    cardRepository = CardRepository();

    _changeNotifier.addListener(_refreshIfNeeded);
    _loadInitialData();
    _loadFirstDeckStatus();
    _loadTags();
    // WidgetsBinding.instance.addPostFrameCallback((_) => launchWelcomeDialog());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => launchBackendMigrationNotice());
  }

  Future<void> _loadInitialData() async {
    final gen = ++_refreshGen;
    try {
      final results = await Future.wait([
        deckRepository.getAllDecks(),
        setRepository.getAllSets(),
        cubeRepository.getAllCubes(),
      ]);
      if (mounted && gen == _refreshGen) {
        setState(() {
          _decks = results[0] as List<Deck>;
          _sets = results[1] as List<Set>;
          _cubes = results[2] as List<Cube>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
    final gen = ++_refreshGen;
    try {
      final results = await Future.wait([
        deckRepository.getAllDecks(),
        setRepository.getAllSets(),
        cubeRepository.getAllCubes(),
      ]);
      if (mounted && gen == _refreshGen) {
        setState(() {
          _decks = results[0] as List<Deck>;
          _sets = results[1] as List<Set>;
          _cubes = results[2] as List<Cube>;
        });
      }
    } catch (_) {
      // Keep existing data on error
    }
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
          overlayStyle:
              ExpandableFabOverlayStyle(color: Colors.black87.withAlpha(0)),
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
                final XFile? image =
                    await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => deckImageProcessing(
                            filePath: image.path,
                            captureSource: CaptureSource.gallery,
                          )));
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
                    MaterialPageRoute(builder: (context) => DeckScanner()));
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
          child: Row(children: [
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
                }),
            IconButton(
                tooltip: "Draft BLE",
                icon: Icon(Icons.diversity_3),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => DraftLobbyScreen()))),
            Spacer(),
            IconButton(
                tooltip: "Settings Menu",
                icon: Icon(Icons.settings),
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (context) => Settings()))
                        .then((_) async {
                      await _loadFirstDeckStatus();
                      setState(() {});
                    })),
          ]),
        ),
        body: AnimatedSwitcher(
            duration: Duration(milliseconds: 500),
            child: Builder(builder: (context) {
              if (_isLoading) {
                return const Center(
                    key: ValueKey('loading'),
                    child: CircularProgressIndicator());
              }

              if (_decks.isEmpty) {
                return Center(
                    key: ValueKey('empty'),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 20,
                        children: [
                      Spacer(flex: 4),
                      Text("No decks found",
                          style: TextStyle(fontSize: 20)),
                      Spacer(flex: 3),
                      Text('Use the "+" button below to add a deck',
                          style: TextStyle(
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).hintColor)),
                      Spacer(flex: 3)
                    ]));
              }

              List<Deck> filteredDecks = currentFilter != null
                  ? _decks
                      .where((deck) => currentFilter!.matchesDeck(deck))
                      .toList()
                  : _decks;
              filteredDecks.sort((a, b) => b.ymd.compareTo(a.ymd));

              return KeyedSubtree(
                key: ValueKey('list'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currentFilter != null)
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        child: createFilterChips(
                            currentFilter!, _sets, _cubes),
                      ),
                    Expanded(
                        child: ListView.separated(
                      itemCount: filteredDecks.length,
                      separatorBuilder: (context, index) =>
                          Divider(indent: 20, endIndent: 20),
                      itemBuilder: (context, index) {
                        return generateSlidableDeckTile(
                            filteredDecks, _sets, _cubes, index);
                      },
                    ))
                  ],
                ),
              );
            }))
    );
  }

  void showTextDeckCreator() {
    showDialog(
      context: context,
      builder: (context) => DeckTextEditor(
        deckRepository: deckRepository,
        cardRepository: cardRepository,
        onSave: (mainboard, sideboard) => refreshDecks(),
        isEditing: false,
      ),
    );
  }

  Widget generateSlidableDeckTile(
      List<Deck> decks, List<Set> sets, List<Cube> cubes, int index) {
    return DeckTile(
      deck: decks[index],
      sets: sets,
      cubes: cubes,
      showFirstDeckHint: !_hasSeenOverviewTutorial && index == 0,
      onFirstDeckViewed: _markFirstDeckSeen,
      onEdit: () => showDeckEditDialog(
        context,
        deck: decks[index],
        sets: sets,
        cubes: cubes,
        allTags: allTags,
        deckRepository: deckRepository,
        onSaved: () { refreshDecks(); _loadTags(); },
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
          final availableSets = _sets
              .where((set) => _decks.any((deck) => deck.setId == set.code))
              .toList();
          final availableCubes = _cubes
              .where((cube) => _decks
                  .any((deck) => deck.cubecobraId == cube.cubecobraId))
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
                        : "Choose Date Range"),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                        "Wins Range: ${winRange.start.round()} - ${winRange.end.round()}"),
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
                  SizedBox(height: 5),
                  DropdownMenu(
                    hintText: "Select $draftType",
                    dropdownMenuEntries: draftType == "set"
                        ? availableSets
                            .map((set) => DropdownMenuEntry(
                                value: set.code, label: set.name))
                            .toList()
                        : availableCubes
                            .map((cube) => DropdownMenuEntry(
                                value: cube.cubecobraId, label: cube.name))
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

  Widget createFilterChips(Filter filter, List<Set> sets, List<Cube> cubes) {
    return Wrap(
      spacing: 5,
      runSpacing: -5,
      children: [
        if (filter.setId != null)
          Chip(
            label: Text(
                "Set: ${sets.firstWhere((set) => set.code == filter.setId).name}"),
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
            label: Text(
                "Cube: ${cubes.firstWhere((cube) => cube.cubecobraId == filter.cubecobraId).name}"),
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
            label: Text(
                "Wins: ${filter.minWins == filter.maxWins ? filter.minWins : '${filter.minWins}-${filter.maxWins}'}"),
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
          ...filter.includedColors
              .map((color) => Chip(
                    label: Text(""),
                    avatar: SvgPicture.asset(
                      "assets/svg_icons/$color.svg",
                      height: 18,
                    ),
                    side: BorderSide(color: Colors.blue.shade200),
                    onDeleted: () => setState(() {
                      final newIncludedColors =
                          List<String>.from(filter.includedColors)
                            ..remove(color);
                      currentFilter =
                          filter.copyWith(includedColors: newIncludedColors);
                      if (currentFilter!.isEmpty()) {
                        currentFilter = null;
                      }
                    }),
                    labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                    padding: EdgeInsets.all(6),
                  ))
              .toList(),
        if (filter.excludedColors.isNotEmpty)
          ...filter.excludedColors
              .map((color) => Chip(
                    label: Text(""),
                    avatar: SvgPicture.asset(
                      "assets/svg_icons/$color.svg",
                      height: 18,
                    ),
                    side: BorderSide(color: Colors.red.shade200),
                    onDeleted: () => setState(() {
                      final newExcludedColors =
                          List<String>.from(filter.excludedColors)
                            ..remove(color);
                      currentFilter =
                          filter.copyWith(excludedColors: newExcludedColors);
                      if (currentFilter!.isEmpty()) {
                        currentFilter = null;
                      }
                    }),
                    labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                    padding: EdgeInsets.all(6),
                  ))
              .toList(),
        if (filter.tags.isNotEmpty)
          ...filter.tags
              .map((tag) => Chip(
                    label: Text("Tag: $tag"),
                    onDeleted: () => setState(() {
                      final newTags = List<String>.from(filter.tags)
                        ..remove(tag);
                      currentFilter = filter.copyWith(tags: newTags);
                      if (currentFilter!.isEmpty()) {
                        currentFilter = null;
                      }
                    }),
                    labelPadding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                    padding: EdgeInsets.all(6),
                  ))
              .toList(),
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
      TextStyle titleStyle =
          TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
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
              SizedBox(
                height: paragraphBreak,
              ),
              Text("Welcome to SnapDrafter!",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(
                height: paragraphBreak,
              ),
              Text(
                "Getting Started",
                style: titleStyle,
              ),
              Text("I try to make the interface as intuitive as possible, but "
                  "if can't figure something out, you can find some additional "
                  "information in 'Settings > Help'."),
              SizedBox(
                height: paragraphBreak,
              ),
              Text(
                "Feedback",
                style: titleStyle,
              ),
              Text("In case you find a bug, have ideas for how things could "
                  "be improved, or features that are missing, I'd love to hear "
                  "your feedback."),
              Text("Clicking 'Settings > Feedback' will give you an invite to "
                  "the SnapDrafter Discord server."),
              SizedBox(
                height: paragraphBreak,
              ),
              Text(
                "Support",
                style: titleStyle,
              ),
              Text("My aim is to keep SnapDrafter free, ad-free, and available"
                  " to as many cube-lovers as possible. Donations make that "
                  "possible."),
              Text("You can find links in 'Settings > Donations'.")
            ],
          ),
          actions: [
            TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await prefs.setBool("welcome_popup_seen", true);
                },
                child: Text("Close")),
          ],
        ),
      );
    }
  }

  /// One-time notice about the backend change from scryfall_id to oracle_id
  /// for card identifiers. Only shown to users with existing data, and only
  /// once.
  Future launchBackendMigrationNotice() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenNotice = prefs.getBool("oracle_migration_notice_seen") ?? false;
    if (hasSeenNotice) return;

    final dbHelper = DatabaseHelper();
    final deckCount = await dbHelper.countRows('decks') ?? 0;
    final cubeCount = await dbHelper.countRows('cubes') ?? 0;
    if (deckCount == 0 && cubeCount == 0) return;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text("Backend Change Notice"),
          content: Text(
              "SnapDrafter has moved from scryfall_id to oracle_id as the "
              "card identifier.\n\n"
              "This is a large backend change, so you should create a new "
              "backup.\n\n"
              "Importing from old backups will cause some cards to be "
              "dropped, but the original deck image will still be imported "
              "just fine."),
          actions: [
            TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await prefs.setBool("oracle_migration_notice_seen", true);
                },
                child: Text("Got it")),
            ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await prefs.setBool("oracle_migration_notice_seen", true);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => BackupSettings()),
                  );
                },
                child: Text("Back up now")),
          ],
          actionsAlignment: MainAxisAlignment.spaceEvenly,
        ),
      );
    }
  }

}
