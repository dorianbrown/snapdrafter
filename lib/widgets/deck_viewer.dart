import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;
import 'package:diffutil_dart/diffutil.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import '/utils/data.dart';
import '/utils/models.dart';

DeckStorage _deckStorage = DeckStorage();

TextStyle _headerStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline
);

class DeckViewer extends StatefulWidget {
  final int deckId;
  const DeckViewer({super.key, required this.deckId});

  @override
  DeckViewerState createState() => DeckViewerState(deckId);
}

class DeckViewerState extends State<DeckViewer> {
  final int deckId;
  DeckViewerState(this.deckId);

  late Future<List<Deck>> decksFuture;
  late Future<List<Card>> allCardsFuture;
  List<String> renderValues = ["text", "type"];
  bool? showManaCurve = false;

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
    decksFuture = _deckStorage.getAllDecks();
    allCardsFuture = _deckStorage.getAllCards();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([decksFuture, allCardsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(),
          );
        } else {
          final decks = snapshot.data![0] as List<Deck> ;
          final allCards = snapshot.data![1] as List<Card>;
          final deck = decks.where((deck) => deck.id == deckId).first;
          return Scaffold(
            appBar: AppBar(title: Text("Deck $deckId")),
            body: Container(
              margin: const EdgeInsets.only(bottom: 20),
              alignment: Alignment.topCenter,
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  Row(
                    spacing: 8,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DropdownMenu(
                        label: const Text("Display"),
                        initialSelection: "text",
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
                        initialSelection: "type",
                        inputDecorationTheme: myInputDecorationTheme,
                        textStyle: const TextStyle(fontSize: 12),
                        dropdownMenuEntries: [
                          DropdownMenuEntry(value: "type", label: "Type"),
                          DropdownMenuEntry(value: "color", label: "Color")
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
                                showManaCurve = value;
                                setState(() {});
                              }
                          ),
                        ],
                      )
                    ]
                  ),
                  Divider(height: 30),
                  if (showManaCurve!) ...generateManaCurve(deck.cards),
                  ...generateDeckView(deck, renderValues)
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              heroTag: "Btn1",
              onPressed: () {
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
              },
              child: const Icon(Icons.edit),
            ),
          );
        }
      }
    );
  }

  findChangesAndUpdate(String newText, String originalText, List<Card> allCards, Deck deck) {
    // We want an exact match on card names. Notify user with snackbar if match not exact.
    final textDiff = calculateListDiff(originalText.split("\n"), newText.split("\n"), detectMoves: false);
    List<Card> cardsCopy = List.from(deck.cards);

    for (var update in textDiff.getUpdatesWithData()) {
      if (update is DataInsert) {
        update as DataInsert<String>;
        Card? matchedCard = allCards.firstWhereOrNull((card) => card.title == update.data);
        if (matchedCard == null) {
          // TODO: Figure out how to show snackbar inside AlertDialog
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Card not found: '${update.data}'")));
          debugPrint("Card not found: $update.data");
          return;
        }
        cardsCopy.insert(update.position, matchedCard);
      }
      if (update is DataRemove) {
        update as DataRemove<String>;
        cardsCopy.removeAt(update.position);
      }
    }
    setState(() {
      deck.cards = cardsCopy;
    });
    _deckStorage.updateDecklist(deck.id, cardsCopy).then((_) {
      Navigator.of(context).pop();
    });
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
    var rows = (renderValues[0] == "text") ? 1 : 2;

    final groupingAttribute = renderValues[1];
    final getAttribute = (groupingAttribute == "type")
        ? (card) => card.type
        : (card) => card.color();
    final uniqueGroupings =
    (groupingAttribute == "type") ? typeOrder : colorOrder;

    for (String attribute in uniqueGroupings) {
      List<Widget> header = [
        Container(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
          child: Text(attribute, style: _headerStyle))
      ];

      deck.cards.sort((a, b) => a.manaValue.compareTo(b.manaValue));
      List<Widget> cardWidgets = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .map((card) => renderCard(card))
          .toList();

      List<Widget> typeList = [];
      List<Widget> rowChildren = [];
      for (int i = 0; i < cardWidgets.length; i++) {
        rowChildren.add(
          Expanded(
            child: cardWidgets[i]
          )
        );
        if (((i + 1) % rows == 0) || (i == cardWidgets.length - 1)) {
          typeList.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: rowChildren,
            )
          );
          rowChildren = [];
        }
      }

      if (cardWidgets.isNotEmpty) {
        deckView.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: header + typeList
          )
        );
      }
    }
    return deckView;
  }

  Widget createTextCard(Card card) {
    return Row(
      spacing: 8,
      children: [
        GestureDetector(
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
          child: Text(
            card.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
        card.createManaCost()
      ],
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

  Widget createVisualCardPopup(Card card) {
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
        child: FittedBox(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Image.network(card.imageUri!),
          )
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

  @override
  void initState() {
    super.initState();
    rulingsFuture = getRulingsData(widget.card.scryfallId);
    rulingsFuture.then((_) => setState(() {}));
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