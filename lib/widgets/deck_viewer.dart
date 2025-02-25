import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart'
as charts;

import '/utils/utils.dart';
import '/utils/data.dart';
import '/utils/models.dart' as models;
import 'download_screen.dart';

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
  late Future<List<models.Deck>> decksFuture;
  DeckViewerState(this.deckId);
  List<String> renderValues = ["text", "type"];
  bool? showManaCurve = true;

  @override
  void initState() {
    super.initState();
    decksFuture = _deckStorage.getAllDecks();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<models.Deck>>(
        future: decksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(),
            );
          } else {
            final List<models.Deck> decks = snapshot.data!;
            final deck = decks[deckId - 1];
            return Scaffold(
              appBar: AppBar(title: Text(deck.name)),
              body: Container(
                // margin: EdgeInsets.fromLTRB(50, 25, 50, 25),
                alignment: Alignment.topCenter,
                child: ListView(
                  padding: EdgeInsets.all(10),
                  children: [
                    Row(
                        spacing: 8,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DropdownMenu(
                            width: 0.3 * MediaQuery.of(context).size.width,
                            label: Text("Display"),
                            initialSelection: "text",
                            inputDecorationTheme: createDropdownStyling(),
                            textStyle: TextStyle(fontSize: 12),
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
                            width: 0.3 * MediaQuery.of(context).size.width,
                            label: Text("Group By"),
                            initialSelection: "type",
                            inputDecorationTheme: createDropdownStyling(),
                            textStyle: TextStyle(fontSize: 12),
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
                              Text("Show Curve", style: TextStyle(height: 0.2, fontSize: 7)),
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
                      builder: (context) => Dialog(
                          child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: TextFormField(
                                expands: true,
                                readOnly: true,
                                keyboardType: TextInputType.multiline,
                                maxLines: null,
                                minLines: null,
                                controller: controller,
                                onTap: () => controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.value.text.length),
                              ))));
                },
                child: const Icon(Icons.share),
              ),
            );
          }
        });
  }

  List<Widget> generateManaCurve(List<models.Card> cards) {
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
            .where((card) => card.type != "Creature")
            .length
      });
      creatureSeries.add({
        "manaValue": (val < 7) ? val.toString() : "7+",
        "count": cards
            .where((card) => condition(card))
            .where((card) => card.type == "Creature")
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
            behaviors: [charts.SeriesLegend()])));
    return outputChildren;
  }

  List<Widget> generateDeckView(models.Deck deck, List<String> renderValues) {
    // Initial setup for rendering
    final List<Widget> deckView = [];

    var renderCard =
    (renderValues[0] == "text") ? createTextCard : createVisualCard;
    var rows = (renderValues[0] == "text") ? 1 : 2;

    final groupingAttribute = renderValues[1];
    final getAttribute = (groupingAttribute == "type")
        ? (card) => card.type
        : (card) => card.color();
    final uniqueGroupings =
    (groupingAttribute == "type") ? models.typeOrder : models.colorOrder;

    for (String attribute in uniqueGroupings) {
      List<Widget> header = [
        Container(
            padding: EdgeInsets.fromLTRB(0, 20, 0, 5),
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
        rowChildren.add(SizedBox(
            width: (0.94 / rows) * MediaQuery.of(context).size.width,
            child: cardWidgets[i]));
        if (((i + 1) % rows == 0) || (i == cardWidgets.length - 1)) {
          typeList.add(Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: rowChildren,
          ));
          rowChildren = [];
        }
      }

      if (cardWidgets.isNotEmpty) {
        deckView.add(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: header + typeList));
      }
    }
    return deckView;
  }

  Widget createTextCard(models.Card card) {
    return Row(
      spacing: 8,
      children: [
        GestureDetector(
          onTap: () => showDialog(
              context: context,
              builder: (context) => Container(
                  padding: EdgeInsets.all(30),
                  child: createVisualCard(card)
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

  // FIXME: This function calling itself is a problem. We'll need make a split
  // somewhere between showing dialog, and showing normal card images.
  Widget createVisualCard(models.Card card) {
    return Container(
        padding: EdgeInsets.all(2),
        child: GestureDetector(
            onTap: () => showDialog(
                context: context,
                builder: (context) => Container(
                    padding: EdgeInsets.all(30), child: createVisualCard(card)
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

  InputDecorationTheme createDropdownStyling() {
    return InputDecorationTheme(
      labelStyle: TextStyle(fontSize: 10),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints.tight(const Size.fromHeight(40)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}