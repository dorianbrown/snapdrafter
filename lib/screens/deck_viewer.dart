import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:diffutil_dart/diffutil.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:loader_overlay/loader_overlay.dart';
import 'package:share_plus/share_plus.dart';

import '/utils/data.dart';
import '/utils/models.dart';
import '/utils/deck_image_generator.dart';

const _headerStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    decoration: TextDecoration.underline
);

class DeckViewer extends StatefulWidget {
  final Deck deck;
  const DeckViewer({super.key, required this.deck});

  @override
  DeckViewerState createState() => DeckViewerState(deck);
}

class DeckViewerState extends State<DeckViewer> {
  final Deck deck;
  DeckViewerState(this.deck);

  final DeckChangeNotifier _notifier = DeckChangeNotifier();
  List<Card>? allCards;
  late DeckStorage _deckStorage;
  List<String> renderValues = ["text", "type"];
  bool? showManaCurve = false;
  // These are used for dropdown menus controlling how decklist is displayed
  TextEditingController displayController = TextEditingController(text: "Text");
  TextEditingController sortingController = TextEditingController(text: "Type");

  final myInputDecorationTheme = InputDecorationTheme(
    labelStyle: TextStyle(fontSize: 10),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    constraints: BoxConstraints.tight(const Size.fromHeight(40)),
    border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    _deckStorage = DeckStorage();
    final cards = await _deckStorage.getAllCards();
    allCards = cards;
  }

  @override
  Widget build(BuildContext context) {
    return LoaderOverlay(
        overlayWidgetBuilder: (_) { //ignored progress for the moment
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: Colors.deepPurpleAccent,
                ),
                SizedBox(height: 50,),
                Text("Creating Decklist Image...", style: TextStyle(fontSize: 16, color: Colors.white)),
              ],
            )
          );
        },
        overlayColor: Colors.black38.withAlpha(200),
        child: Scaffold(
          appBar: AppBar(
            actions: generateControls(),
          ),
          body: Container(
            alignment: Alignment.topCenter,
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (showManaCurve!) ...generateManaCurve(deck.cards),
                Container(
                    padding: EdgeInsets.fromLTRB(10, 6, 15, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text("${deck.cards.length} cards", style: TextStyle(fontSize: 16, height: 1.5))
                      ],
                    )
                ),
                ...generateDeckView(deck, renderValues)
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
                  onPressed: () => allCards != null ? showBasicsEditor(deck, allCards!) : null
                ),
                Spacer(),
                IconButton(
                  tooltip: "Edit",
                  icon: Icon(Icons.edit),
                  onPressed: () => allCards != null ? showDeckEditor(deck, allCards!) : null,
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
      )
    );
  }

  Future shareDeck(Deck deck) async {

    img.Image? image = await generateDeckImage(deck);

    // Convert to memory bytes
    Uint8List bytes = Uint8List.fromList(img.encodePng(image));

    final params = ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png')]
    );

    SharePlus.instance.share(params);
  }

  findChangesAndUpdate(String newText, String originalText, List<Card> allCards, Deck deck) {
    // We want an exact match on card names. Notify user with snackbar if match not exact.
    final textDiff = calculateListDiff(originalText.split("\n"), newText.split("\n"), detectMoves: false);
    List<Card> cardsCopy = List.from(deck.cards);

    for (var update in textDiff.getUpdatesWithData()) {
      if (update is DataInsert) {
        update as DataInsert<String>;
        debugPrint("Update at [${update.position}]: ${update.data}");
        final regex = RegExp(r'^(\d)\s(.+)$');
        var regexMatch = regex.allMatches(update.data);
        int count = int.parse(regexMatch.first[1]!);
        String cardName = regexMatch.first[2]!;
        Card? matchedCard = allCards.firstWhereOrNull((card) => card.name == cardName);
        if (matchedCard == null) {
          // TODO: Figure out how to show snackbar inside AlertDialog
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Card not found: '${update.data}'")));
          debugPrint("Card not found: $update.data");
          return;
        }
        for (int i = 0; i < count; i++) {
          cardsCopy.add(matchedCard);
        }
      }
      if (update is DataRemove) {
        update as DataRemove<String>;
        final regex = RegExp(r'^(\d)\s(.+)$');
        var regexMatch = regex.allMatches(update.data);
        String cardName = regexMatch.first[2]!;
        cardsCopy.removeWhere((card) => card.name == cardName);
      }
    }
    setState(() {
      deck.cards = cardsCopy;
      _notifier.markNeedsRefresh();
    });
    _deckStorage.updateDecklist(deck.id, cardsCopy).then((_) {
      Navigator.of(context).pop();
    });
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
                  ...['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'].map((name) {
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
                      'G': 0
                    };
                    
                    // Count colored symbols in each card's mana cost
                    for (var card in deck.cards) {
                      if (card.manaCost != null) {
                        for (var symbol in ['W', 'U', 'B', 'R', 'G']) {
                          colorCounts[symbol] = colorCounts[symbol]! + 
                            RegExp(symbol).allMatches(card.manaCost!).length;
                        }
                      }
                    }
                    
                    // Count non-basic lands
                    int nonBasicLands = deck.cards.where((card) => 
                      card.type == 'Land' && 
                      !['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'].contains(card.name)
                    ).length;
                    
                    // Calculate total basics needed (17 - non-basic lands)
                    int totalBasics = 17 - nonBasicLands;
                    
                    // Calculate total colored symbols
                    int totalSymbols = colorCounts.values.reduce((a, b) => a + b);

                    // TODO: Take into account the mana production of non-basic lands

                    setDialogState(() {
                      // Calculate basic land distribution based on color requirements
                      basicCounts['Plains'] = (colorCounts['W']! / totalSymbols * totalBasics).round();
                      basicCounts['Island'] = (colorCounts['U']! / totalSymbols * totalBasics).round();
                      basicCounts['Swamp'] = (colorCounts['B']! / totalSymbols * totalBasics).round();
                      basicCounts['Mountain'] = (colorCounts['R']! / totalSymbols * totalBasics).round();
                      basicCounts['Forest'] = (colorCounts['G']! / totalSymbols * totalBasics).round();
                      
                      // Ensure we don't exceed total basics
                      int currentTotal = basicCounts.values.reduce((a, b) => a + b);
                      if (currentTotal > totalBasics) {
                        // Reduce largest count to match
                        var maxEntry = basicCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
                        basicCounts[maxEntry.key] = maxEntry.value - (currentTotal - totalBasics);
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
                    List<Card> newCards = deck.cards.where((c) =>
                      !['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'].contains(c.name)
                    ).toList();

                    // Add new basic lands
                    for (var entry in basicCounts.entries) {
                      Card basicLand;
                      switch (entry.key) {
                        case 'Plains': basicLand = plains; break;
                        case 'Island': basicLand = island; break;
                        case 'Swamp': basicLand = swamp; break;
                        case 'Mountain': basicLand = mountain; break;
                        case 'Forest': basicLand = forest; break;
                        default: continue;
                      }
                      newCards.addAll(List.filled(entry.value, basicLand));
                    }

                    // Update both local deck state and database
                    setState(() {
                      deck.cards = newCards;
                      _notifier.markNeedsRefresh();
                    });
                    // Force refresh the FutureBuilder by creating a new future
                    _deckStorage.updateDecklist(deck.id, newCards).then((_) {
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

  List<Widget> generateControls() {
    return [Row(
      spacing: 8,
      children: [
        DropdownMenu(
          label: const Text("Display"),
          controller: displayController,
          inputDecorationTheme: myInputDecorationTheme,
          textStyle: const TextStyle(fontSize: 12),
          dropdownMenuEntries: [
            DropdownMenuEntry(value: "text", label: "Text"),
            DropdownMenuEntry(value: "image", label: "Images")
          ],
          onSelected: (value) {
            renderValues[0] = value!;
            setState(() {});
          },
        ),
        DropdownMenu(
          label: const Text("Group By"),
          controller: sortingController,
          inputDecorationTheme: myInputDecorationTheme,
          textStyle: const TextStyle(fontSize: 12),
          dropdownMenuEntries: [
            DropdownMenuEntry(value: "type", label: "Type"),
            DropdownMenuEntry(value: "color", label: "Color"),
            // DropdownMenuEntry(value: "mv", label: "Mana Value")
          ],
          onSelected: (value) {
            renderValues[1] = value!;
            setState(() {});
          },
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 2,
          children: [
            const Text("Show Curve", style: TextStyle(height: 0.2, fontSize: 7)),
            Checkbox(
                visualDensity: VisualDensity.compact,
                value: showManaCurve,
                onChanged: (bool? value) {
                  setState(() {
                    showManaCurve = value;
                  });
                }
            ),
          ],
        ),
        SizedBox(width: 0,)
      ],
    )];
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
              titleTextStyle: TextStyle(fontSize: 16),
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
                    child: const Text("Back")
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
                )
              ],
            );
          }
        );
      }
    );
  }

  void showDeckEditor(Deck deck, List<Card> allCards) {
    final controller = TextEditingController(text: deck.generateTextExport());
    showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: TextFormField(
            expands: true,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            minLines: null,
            controller: controller,
          ),
          actions: [
            TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: controller.text));
                },
                child: const Text("Copy All")
            ),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Discard")
            ),
            TextButton(
                onPressed: () => findChangesAndUpdate(controller.text, deck.generateTextExport(), allCards, deck),
                child: const Text("Save")
            )
          ],
        )
    );
  }

  List<Widget> generateManaCurve(List<Card> cards) {
    List<Widget> outputChildren = [Text("Mana Curve", style: _headerStyle)];

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
            .length
      });
      creatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type == "Creature" && card.type != "Land")
            .length
      });
    }

    List<charts.Series<dynamic, String>> seriesList = [
      charts.Series(
          id: "Non-Creature",
          domainFn: (datum, _) => datum["manaValue"],
          measureFn: (datum, _) => datum["count"],
          data: nonCreatureSeries),
      charts.Series(
          id: "Creature",
          domainFn: (datum, _) => datum["manaValue"],
          measureFn: (datum, _) => datum["count"],
          data: creatureSeries)
    ];

    outputChildren.add(SizedBox(
        height: 200,
        child: charts.BarChart(
            animate: false,
            seriesList,
            barGroupingType: charts.BarGroupingType.stacked,
            primaryMeasureAxis: charts.NumericAxisSpec(
                tickProviderSpec: charts.BasicNumericTickProviderSpec(
                    dataIsInWholeNumbers: true, desiredMinTickCount: 4)),
            behaviors: [charts.SeriesLegend(showMeasures: true)])));
    return outputChildren;
  }

  List<Widget> generateDeckView(Deck deck, List<String> renderValues) {
    // Initial setup for rendering
    final List<Widget> deckView = [];

    var renderCard =
    (renderValues[0] == "text") ? createTextCard : createVisualCardPopup;

    // TODO: Rework this to accept mana_value as grouping
    final groupingAttribute = renderValues[1];
    final getAttribute = (groupingAttribute == "type")
        ? (card) => card.type
        : (card) => card.color();
    final uniqueGroupings =
    (groupingAttribute == "type") ? typeOrder : colorOrder;

    // Here we loop over unique groupings and generate the widgets for each grouping
    for (String attribute in uniqueGroupings) {

      // Here we generate all the widgets within the current grouping
      deck.cards.sort((a, b) => a.manaValue.compareTo(b.manaValue));
      List<Widget> cardWidgets = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries.map((entry) => renderCard(entry.key, entry.value))
          .toList();

      int numCards = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .length;

      // Generate the header text
      List<Widget> header = [
        Container(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
          child: Text("$attribute ($numCards)", style: _headerStyle))
      ];

      if (cardWidgets.isNotEmpty) {
        deckView.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: header + (
              (renderValues[0] == "text")
                ? cardWidgets
                : [GridView.count(
                  physics: NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.72,
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  children: cardWidgets,
                )]
            )
          )
        );
      }
    }
    return deckView;
  }

  Widget createTextCard(Card card, int count) {
    return GestureDetector(
      onTap: () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text("Card Information", style: TextStyle(fontSize: 18),),
            content: CardPopup(card: card),
            actions: [
              TextButton(
                child: Text("Dismiss"),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          )
      ),
      child: Row(
        spacing: 8,
        children: [
          Text(
            (count > 1) ? "$count x ${card.title}" : card.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          card.createManaCost()
        ],
      )
    );
  }

  Widget createVisualCard(Card card) {
    return FittedBox(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Image.network(card.imageUri!),
      )
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
            title: Text("Card Information", style: TextStyle(fontSize: 18),),
            content: CardPopup(card: card),
            actions: [
              TextButton(
                child: Text("Dismiss"),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          )
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
              )
          ],
        )
      )
    );
  }
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
              )
          )
        ),
        FutureBuilder(
            future: cardDataFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final Map<String, dynamic> cardData = snapshot.data!;
                return displayCardData(cardData);
              }
              return const CircularProgressIndicator();
            }
        ),
        Divider(height: 4,),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [Text("Rulings", style: _headerStyle)]
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
                    )
                ]
              );
            }
            return const CircularProgressIndicator();
          }
        ),
      ]
    );
  }

  Future getCardData(String scryfallId) async {
    final response = await http.get(Uri.parse("https://api.scryfall.com/cards/$scryfallId"));
    if (response.statusCode == 200) {
      final payload = json.decode(response.body);
      return payload;
    } else {
      throw Exception("Failed to load rulings");
    }
  }

  Future getRulingsData(String scryfallId) async {
    final response = await http.get(Uri.parse("https://api.scryfall.com/cards/$scryfallId/rulings"));
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
    children: widgets
  );
}
