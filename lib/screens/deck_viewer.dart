import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:community_charts_flutter/community_charts_flutter.dart'
    as charts;
import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:loader_overlay/loader_overlay.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:snapdrafter/data/repositories/card_repository.dart';
import 'package:url_launcher/url_launcher.dart';

import '/utils/deck_image_generator.dart';
import '/widgets/deck_text_editor.dart';
import '/widgets/deck_edit_dialog.dart';
import '/widgets/display_token.dart';
import '/data/repositories/token_repository.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/cube_repository.dart';
import '/data/models/card.dart';
import '/data/models/deck.dart';
import '/data/models/deck_upsert.dart';
import '/data/models/set.dart';
import '/data/models/cube.dart';
import '/utils/constants.dart';
import '/utils/deck_change_notifier.dart';

const _headerStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline,
);

const _sideboardHeaderStyle = TextStyle(
  fontSize: 24, // Larger than the regular header
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline,
);

class DeckViewer extends StatefulWidget {
  final Deck deck;
  const DeckViewer({super.key, required this.deck});

  @override
  DeckViewerState createState() => DeckViewerState(deck);
}

class DeckViewerState extends State<DeckViewer> {
  Deck deck;
  DeckViewerState(this.deck);

  final DeckChangeNotifier _notifier = DeckChangeNotifier();
  List<Card>? allCards;
  late CardRepository cardRepository;
  late TokenRepository tokenRepository;
  late DeckRepository deckRepository;
  Map groupedTokens = {};
  List<Set> _sets = [];
  List<Cube> _cubes = [];
  List<String> _allTags = [];
  bool _dataLoaded = false;
  int columnCount = 3;

  @override
  void initState() {
    super.initState();
    _loadCards();
    tokenRepository = TokenRepository();
    deckRepository = DeckRepository();
    _loadSetsAndCubesAndTags();
    tokenRepository.getDeckTokens(deck.id).then((val) {
      setState(() {
        groupedTokens = val;
      });
    });
  }

  String get _setCubeLabel {
    if (deck.cubecobraId != null && _cubes.isNotEmpty) {
      try {
        return _cubes.firstWhere((c) => c.cubecobraId == deck.cubecobraId).name;
      } catch (_) {}
    }
    if (deck.setId != null && _sets.isNotEmpty) {
      try {
        return _sets.firstWhere((s) => s.code == deck.setId).code.toUpperCase();
      } catch (_) {}
    }
    return "—";
  }

  Widget _buildMetadataChip(String label, {IconData? icon}) {
    final chipColor = Colors.white60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 0.5,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: chipColor),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCards() async {
    cardRepository = CardRepository();
    final cards = await cardRepository.getAllCards();
    allCards = cards;
  }

  Future<void> _loadSetsAndCubesAndTags() async {
    final results = await Future.wait([
      SetRepository().getAllSets(),
      CubeRepository().getAllCubes(),
      deckRepository.getAllTags(),
    ]);
    setState(() {
      _sets = results[0] as List<Set>;
      _cubes = results[1] as List<Cube>;
      _allTags = results[2] as List<String>;
      _dataLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LoaderOverlay(
      overlayWidgetBuilder: (_) {
        //ignored progress for the moment
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepPurpleAccent),
              SizedBox(height: 50),
              Text(
                "Creating Decklist Image...",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
        );
      },
      overlayColor: Colors.black38.withAlpha(200),
      child: Scaffold(
        appBar: AppBar(
          title: deck.name != null && deck.name!.isNotEmpty
              ? Text(deck.name!, overflow: TextOverflow.ellipsis)
              : null,
          actionsPadding: EdgeInsets.fromLTRB(0, 0, 10, 0),
          actions: [
            Row(
              children: [
                PopupMenuButton<int>(
                  initialValue: columnCount,
                  tooltip: "Columns",
                  onSelected: (value) => setState(() => columnCount = value),
                  child: IconButton(
                    icon: Icon(switch (columnCount) {
                      2 => Icons.looks_two,
                      3 => Icons.looks_3,
                      4 => Icons.looks_4,
                      _ => Icons.looks_3,
                    }),
                    onPressed: null,
                    disabledColor: Colors.white70,
                  ),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 2,
                      checked: columnCount == 2,
                      child: const Icon(Icons.looks_two),
                    ),
                    CheckedPopupMenuItem(
                      value: 3,
                      checked: columnCount == 3,
                      child: const Icon(Icons.looks_3),
                    ),
                    CheckedPopupMenuItem(
                      value: 4,
                      checked: columnCount == 4,
                      child: const Icon(Icons.looks_4),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: "Edit Deck Info",
                  icon: Icon(Icons.edit, color: Colors.amber.withAlpha(175)),
                  onPressed: _dataLoaded
                      ? () => showDeckEditDialog(
                          context,
                          deck: deck,
                          sets: _sets,
                          cubes: _cubes,
                          allTags: _allTags,
                          deckRepository: deckRepository,
                          onSaved: () async {
                            _notifier.markNeedsRefresh();
                            final decks = await deckRepository.getAllDecks();
                            final updated = decks.firstWhere(
                              (d) => d.id == deck.id,
                            );
                            setState(() => deck = updated);
                          },
                        )
                      : null,
                ),
                IconButton(
                  tooltip: "Delete Deck",
                  icon: Icon(Icons.delete, color: Colors.deepOrange.withAlpha(175)),
                  onPressed: _confirmDeleteViewerDeck,
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(35, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (deck.wins != null) ...[
                        _buildMetadataChip(
                          "${deck.wins ?? 0}-${deck.losses ?? 0}${deck.draws != 0 ? '-${deck.draws}' : ''}",
                          icon: Icons.emoji_events
                        ),
                      ],
                      if (_setCubeLabel != "—") ...[
                        const SizedBox(width: 6),
                        _buildMetadataChip(
                          _setCubeLabel,
                          icon: Icons.apps,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _buildMetadataChip(deck.ymd, icon: Icons.calendar_today),
                      Spacer(),
                      Text(
                        "${deck.cards.length} cards",
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          alignment: Alignment.topCenter,
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              generateManaCurve(deck.cards),
              ...generateDeckView(deck, columnCount),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 65,
          child: Row(
            children: [
              IconButton(
                tooltip: "Sample Starting Hand",
                icon: Icon(Icons.back_hand),
                onPressed: () => showRandomHand(deck),
              ),
              IconButton(
                tooltip: "Add basics",
                icon: Icon(Icons.landscape),
                onPressed: () =>
                    allCards != null ? showBasicsEditor(deck, allCards!) : null,
              ),
              IconButton(
                tooltip: "Show Deck Tokens",
                icon: Icon(Icons.cruelty_free),
                onPressed: groupedTokens.isNotEmpty
                    ? () => showDeckTokens(deck.id)
                    : null,
              ),
              Spacer(),
              // TODO: Broken currently
              // IconButton(
              //   tooltip: "Share to CubeCobra",
              //   icon: SvgPicture.asset(
              //     "assets/app_icons/monochrome_cubecobra.svg",
              //     height: 28,
              //     colorFilter: ColorFilter.mode(
              //         // Theme.of(context).iconTheme.color!,
              //         Theme.of(context).unselectedWidgetColor,
              //         BlendMode.srcIn),
              //   ),
              //   onPressed: () => shareWithCubeCobra(deck),
              // ),
              IconButton(
                tooltip: "Edit Decklist",
                icon: Icon(Icons.format_list_numbered),
                onPressed: () =>
                    allCards != null ? showDeckEditor(deck, allCards!) : null,
              ),
              IconButton(
                tooltip: "View Deck Photo",
                icon: Icon(Icons.image),
                onPressed: deck.imagePath != null
                    ? () =>
                          createInteractiveImageViewer(deck.imagePath!, context)
                    : null,
              ),
              IconButton(
                tooltip: "Share",
                icon: Icon(Icons.share),
                onPressed: () async {
                  context.loaderOverlay.show();
                  await shareDeck(deck);
                  context.loaderOverlay.hide();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteViewerDeck() {
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
              await deckRepository.deleteDeck(deck.id);
              Navigator.of(dialogContext).pop();
              _notifier.markNeedsRefresh();
              Navigator.of(context).pop();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future showDeckTokens(int deckId) async {
    // Create Dialog window to display tokens and associated cards
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          // title: Text("Tokens"),
          insetPadding: EdgeInsets.all(30),
          contentPadding: EdgeInsets.all(10),
          content: Container(
            width: double.maxFinite,
            child: MasonryGridView.count(
              itemCount: groupedTokens.keys.length,
              shrinkWrap: true,
              crossAxisCount: 2,
              itemBuilder: (context, index) => DisplayToken(
                imageUri: groupedTokens.keys.toList()[index],
                cards: groupedTokens.values.toList()[index]["cards"],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Back"),
            ),
          ],
        );
      },
    );
  }

  Future shareDeck(Deck deck) async {
    final ui.Image image = await generateDeckImage(deck);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final imageBytes = byteData!.buffer.asUint8List();
    image.dispose();

    final params = ShareParams(
      files: [XFile.fromData(imageBytes, mimeType: 'image/png')],
    );

    SharePlus.instance.share(params);
  }

  Future showBasicsEditor(Deck deck, List<Card> allCards) async {
    // Get current counts of each basic land type
    Map<String, int> basicCounts = {
      'Plains': deck.cards.where((c) => c.name == 'Plains').length,
      'Island': deck.cards.where((c) => c.name == 'Island').length,
      'Swamp': deck.cards.where((c) => c.name == 'Swamp').length,
      'Mountain': deck.cards.where((c) => c.name == 'Mountain').length,
      'Forest': deck.cards.where((c) => c.name == 'Forest').length,
    };

    // Get all cards to find basic lands
    final plains = allCards.firstWhere((c) => c.name == 'Plains');
    final island = allCards.firstWhere((c) => c.name == 'Island');
    final swamp = allCards.firstWhere((c) => c.name == 'Swamp');
    final mountain = allCards.firstWhere((c) => c.name == 'Mountain');
    final forest = allCards.firstWhere((c) => c.name == 'Forest');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Text('Edit Basic Lands'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Deck colors: ${deck.colors}'),
                  SizedBox(height: 20),
                  ...['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'].map((
                    name,
                  ) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove),
                              onPressed: () {
                                setDialogState(() {
                                  if (basicCounts[name]! > 0) {
                                    basicCounts[name] = basicCounts[name]! - 1;
                                  }
                                });
                              },
                            ),
                            Text('${basicCounts[name]}'),
                            IconButton(
                              icon: Icon(Icons.add),
                              onPressed: () {
                                setDialogState(() {
                                  basicCounts[name] = basicCounts[name]! + 1;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Calculate'),
                  onPressed: () {
                    // Calculate total colored mana symbols in deck
                    Map<String, int> colorCounts = {
                      'W': 0,
                      'U': 0,
                      'B': 0,
                      'R': 0,
                      'G': 0,
                    };

                    // Count colored symbols in each card's mana cost
                    for (var card in deck.cards) {
                      if (card.manaCost != null) {
                        for (var symbol in ['W', 'U', 'B', 'R', 'G']) {
                          colorCounts[symbol] =
                              colorCounts[symbol]! +
                              RegExp(symbol).allMatches(card.manaCost!).length;
                        }
                      }
                    }

                    // Count non-basic lands
                    int nonBasicLands = deck.cards
                        .where(
                          (card) =>
                              card.type == 'Land' &&
                              ![
                                'Plains',
                                'Island',
                                'Swamp',
                                'Mountain',
                                'Forest',
                              ].contains(card.name),
                        )
                        .length;

                    // Calculate total basics needed (17 - non-basic lands)
                    int totalBasics = 17 - nonBasicLands;

                    // Calculate total colored symbols
                    int totalSymbols = colorCounts.values.reduce(
                      (a, b) => a + b,
                    );

                    // TODO: Take into account the mana production of non-basic lands

                    setDialogState(() {
                      // Calculate basic land distribution based on color requirements
                      basicCounts['Plains'] =
                          (colorCounts['W']! / totalSymbols * totalBasics)
                              .round();
                      basicCounts['Island'] =
                          (colorCounts['U']! / totalSymbols * totalBasics)
                              .round();
                      basicCounts['Swamp'] =
                          (colorCounts['B']! / totalSymbols * totalBasics)
                              .round();
                      basicCounts['Mountain'] =
                          (colorCounts['R']! / totalSymbols * totalBasics)
                              .round();
                      basicCounts['Forest'] =
                          (colorCounts['G']! / totalSymbols * totalBasics)
                              .round();

                      // Ensure we don't exceed total basics
                      int currentTotal = basicCounts.values.reduce(
                        (a, b) => a + b,
                      );
                      if (currentTotal > totalBasics) {
                        // Reduce largest count to match
                        var maxEntry = basicCounts.entries.reduce(
                          (a, b) => a.value > b.value ? a : b,
                        );
                        basicCounts[maxEntry.key] =
                            maxEntry.value - (currentTotal - totalBasics);
                      }
                    });
                  },
                ),
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text('Save'),
                  onPressed: () async {
                    // Update deck with new basic land counts
                    List<Card> newCards = deck.cards
                        .where(
                          (c) => ![
                            'Plains',
                            'Island',
                            'Swamp',
                            'Mountain',
                            'Forest',
                          ].contains(c.name),
                        )
                        .toList();

                    // Add new basic lands
                    for (var entry in basicCounts.entries) {
                      Card basicLand;
                      switch (entry.key) {
                        case 'Plains':
                          basicLand = plains;
                          break;
                        case 'Island':
                          basicLand = island;
                          break;
                        case 'Swamp':
                          basicLand = swamp;
                          break;
                        case 'Mountain':
                          basicLand = mountain;
                          break;
                        case 'Forest':
                          basicLand = forest;
                          break;
                        default:
                          continue;
                      }
                      newCards.addAll(List.filled(entry.value, basicLand));
                    }

                    // Update both local deck state and database
                    setState(() {
                      deck.cards = newCards;
                      _notifier.markNeedsRefresh();
                    });
                    // Force refresh the FutureBuilder by creating a new future
                    deckRepository
                        .updateDeck(
                          DeckUpsert(
                            id: deck.id,
                            cards: newCards,
                            sideboard: deck
                                .sideboard, // Make sure to preserve sideboard
                          ),
                        )
                        .then((_) {
                          Navigator.of(context).pop();
                        });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showRandomHand(Deck deck) {
    List<Card> hand = [];
    List<Card> remainingCards = [];

    void drawNewHand() {
      hand = deck.cards.sample(7);
      remainingCards = List.from(deck.cards); // Make copy
      for (var card in hand) {
        remainingCards.remove(card);
      }
      remainingCards.shuffle();
    }

    void drawCard() {
      if (remainingCards.isEmpty) {
        drawNewHand();
      } else {
        hand.add(remainingCards.removeAt(0));
      }
    }

    drawNewHand();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Sample Starting Hand"),
              insetPadding: EdgeInsets.all(15),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * .9,
                child: GridView.count(
                  childAspectRatio: 0.72,
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  children: hand.map((card) => createVisualCard(card)).toList(),
                ),
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Back"),
                ),
                TextButton(
                  onPressed: () {
                    drawCard();
                    setState(() {});
                  },
                  child: const Text("Draw Card"),
                ),
                TextButton(
                  onPressed: () {
                    drawNewHand();
                    setState(() {});
                  },
                  child: const Text("New Hand"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showDeckEditor(Deck deck, List<Card> allCards) {
    showDialog(
      context: context,
      builder: (context) => DeckTextEditor(
        initialText: deck.generateTextExport(),
        deckRepository: deckRepository,
        cardRepository: cardRepository,
        isEditing: true,
        deckId: deck.id,
        onSave: (newMainboard, newSideboard) {
          setState(() {
            deck.cards = newMainboard;
            deck.sideboard = newSideboard;
            _notifier.markNeedsRefresh();
          });
          deckRepository.updateDeck(
            DeckUpsert(
              id: deck.id,
              cards: newMainboard,
              sideboard: newSideboard,
            ),
          );
        },
      ),
    );
  }

  Widget generateManaCurve(List<Card> cards) {
    List<int> manaValues = [0, 1, 2, 3, 4, 5, 6, 7];
    final nonCreatureSeries = [];
    final creatureSeries = [];

    for (var val in manaValues) {
      condition(card) {
        if (val < 7) {
          return (card.manaValue == val);
        } else {
          return (card.manaValue > 6);
        }
      }

      nonCreatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type != "Creature" && card.type != "Land")
            .length,
      });
      creatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type == "Creature" && card.type != "Land")
            .length,
      });
    }

    List<charts.Series<dynamic, String>> seriesList = [
      charts.Series(
        id: "Non-Creature",
        domainFn: (datum, _) => datum["manaValue"],
        measureFn: (datum, _) => datum["count"],
        data: nonCreatureSeries,
      ),
      charts.Series(
        id: "Creature",
        domainFn: (datum, _) => datum["manaValue"],
        measureFn: (datum, _) => datum["count"],
        data: creatureSeries,
      ),
    ];

    return SizedBox(
      height: 200,
      child: charts.BarChart(
        animate: false,
        seriesList,
        barGroupingType: charts.BarGroupingType.stacked,
        primaryMeasureAxis: charts.NumericAxisSpec(
          tickProviderSpec: charts.BasicNumericTickProviderSpec(
            dataIsInWholeNumbers: true,
            desiredMinTickCount: 4,
          ),
        ),
        behaviors: [charts.SeriesLegend(showMeasures: true)],
      ),
    );
  }

  List<Widget> generateDeckView(Deck deck, int columnCount) {
    final List<Widget> deckView = [];

    getAttribute(card) => card.type;
    final uniqueGroupings = typeOrder;

    for (String attribute in uniqueGroupings) {
      deck.cards.sort((a, b) => a.manaValue.compareTo(b.manaValue));
      List<Widget> cardWidgets = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries
          .map((entry) => createVisualCardPopup(entry.key, entry.value))
          .toList();

      int numCards = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .length;

      List<Widget> header = [
        Container(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
          child: Text("$attribute ($numCards)", style: _headerStyle),
        ),
      ];

      if (cardWidgets.isNotEmpty) {
        deckView.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...header,
              GridView.count(
                physics: NeverScrollableScrollPhysics(),
                childAspectRatio: 0.72,
                crossAxisCount: columnCount,
                shrinkWrap: true,
                children: cardWidgets,
              ),
            ],
          ),
        );
      }
    }

    if (deck.sideboard.isNotEmpty) {
      deckView.add(
        Container(
          padding: const EdgeInsets.fromLTRB(0, 30, 0, 10),
          child: Text(
            "Sideboard (${deck.sideboard.length})",
            style: _sideboardHeaderStyle,
          ),
        ),
      );

      deck.sideboard.sort((a, b) => a.manaValue.compareTo(b.manaValue));

      List<Widget> sideboardWidgets = deck.sideboard
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries
          .map((entry) => createVisualCardPopup(entry.key, entry.value))
          .toList();

      deckView.add(
        GridView.count(
          physics: NeverScrollableScrollPhysics(),
          childAspectRatio: 0.72,
          crossAxisCount: columnCount,
          shrinkWrap: true,
          children: sideboardWidgets,
        ),
      );
    }

    return deckView;
  }

  Widget createVisualCard(Card card) {
    return FittedBox(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Image.network(card.imageUri!),
      ),
    );
  }

  Widget createVisualCardPopup(Card card, int count) {
    return Container(
      padding: EdgeInsets.all(2),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text("Card Information", style: TextStyle(fontSize: 18)),
            content: CardPopup(card: card),
            actions: [
              TextButton(
                child: Text("Dismiss"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        child: Stack(
          children: [
            createVisualCard(card),
            if (count > 1)
              Container(
                alignment: Alignment.bottomLeft,
                margin: EdgeInsets.symmetric(vertical: 15, horizontal: 13),
                child: Text(
                  "${count}x",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    background: Paint()
                      ..color = Colors.black.withAlpha(180)
                      ..strokeWidth = 11
                      ..strokeJoin = StrokeJoin.round
                      ..strokeCap = StrokeCap.round
                      ..style = PaintingStyle.stroke,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void shareWithCubeCobra(Deck deck) {
  // Construct query parameters containing list of cards
  Map<String, dynamic> queryParams = {
    "o": deck.cards.map((card) => card.oracleId).toList(),
  };
  // If no sideboard, we omit the "s" key
  if (deck.sideboard.isNotEmpty) {
    queryParams["s"] = deck.sideboard.map((card) => card.oracleId).toList();
  }
  // Launch URL to CubeCobra for importing deck
  Uri cubecobraUri = Uri(
    scheme: "https",
    host: "cubecobra.com",
    path: "cube/records/import",
    queryParameters: queryParams,
  );
  launchUrl(cubecobraUri);
}

void createInteractiveImageViewer(String imagePath, BuildContext context) {
  // This is currently the best approach without knowing the images HxW
  // dimensions. Requires a background, and for
  showDialog(
    context: context,
    builder: (innerContext) {
      return AlertDialog(
        insetPadding: EdgeInsets.zero, // Maximize viewing area
        contentPadding: EdgeInsets.zero, // Maximize viewing area
        actions: [
          TextButton(
            style: ButtonStyle(
              foregroundColor: MaterialStateProperty.all(Colors.white),
              backgroundColor: MaterialStateProperty.all(Colors.black38),
            ),
            child: const Text("Share"),
            onPressed: () async {
              final params = ShareParams(files: [XFile(imagePath)]);
              await SharePlus.instance.share(params);
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            style: ButtonStyle(
              foregroundColor: MaterialStateProperty.all(Colors.white),
              backgroundColor: MaterialStateProperty.all(Colors.black38),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Back"),
          ),
        ],
        content: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                minScale: 1,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Image.file(File(imagePath)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CardPopup extends StatefulWidget {
  final Card card;
  const CardPopup({super.key, required this.card});

  @override
  State<CardPopup> createState() => _CardPopupState();
}

class _CardPopupState extends State<CardPopup> {
  late Future rulingsFuture;
  late Future cardDataFuture;

  @override
  void initState() {
    super.initState();
    rulingsFuture = getRulingsData(widget.card.scryfallId);
    cardDataFuture = getCardData(widget.card.scryfallId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 20,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          child: FittedBox(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Image.network(widget.card.imageUri!),
            ),
          ),
        ),
        FutureBuilder(
          future: cardDataFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final Map<String, dynamic> cardData = snapshot.data!;
              return displayCardData(cardData);
            }
            return const CircularProgressIndicator();
          },
        ),
        Divider(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [Text("Rulings", style: _headerStyle)],
        ),
        FutureBuilder(
          future: rulingsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final rulings = snapshot.data!;
              return Column(
                children: [
                  for (var ruling in rulings)
                    ListTile(
                      contentPadding: EdgeInsets.all(0),
                      title: Text(ruling["published_at"]),
                      subtitle: Text(ruling["comment"]),
                    ),
                ],
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ],
    );
  }

  Future getCardData(String scryfallId) async {
    final response = await http.get(
      Uri.parse("https://api.scryfall.com/cards/$scryfallId"),
      headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'},
    );
    if (response.statusCode == 200) {
      final payload = json.decode(response.body);
      return payload;
    } else {
      throw Exception("Failed to load rulings");
    }
  }

  Future getRulingsData(String scryfallId) async {
    final response = await http.get(
      Uri.parse("https://api.scryfall.com/cards/$scryfallId/rulings"),
      headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'},
    );
    if (response.statusCode == 200) {
      final payload = json.decode(response.body);
      final rulings = payload["data"];
      return rulings;
    } else {
      throw Exception("Failed to load rulings");
    }
  }
}

Widget displayCardData(Map<String, dynamic> cardData) {
  List<dynamic>? cardFaces = cardData["card_faces"];

  final style = TextStyle(fontStyle: FontStyle.italic);

  cardFaces ??= [cardData];

  List<Widget> widgets = [];
  for (var cardFace in cardFaces) {
    widgets += [
      Divider(height: 6),
      Text(cardFace["type_line"], style: style),
      Divider(height: 6, endIndent: 225),
      for (String text in cardFace["oracle_text"].split("\n"))
        Text(text, style: style),
    ];
  }

  return Column(
    spacing: 8,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: widgets,
  );
}
