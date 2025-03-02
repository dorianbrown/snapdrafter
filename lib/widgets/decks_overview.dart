import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '/utils/utils.dart';
import '/utils/data.dart';
import '/utils/models.dart' as models;
import '/widgets/deck_viewer.dart';
import '/widgets/main_menu_drawer.dart';

DeckStorage _deckStorage = DeckStorage();

class MyDecksOverview extends StatelessWidget {
  const MyDecksOverview({super.key});

  @override
  Widget build(BuildContext context) {
    Future<List<models.Deck>> decksFuture = _deckStorage.getAllDecks();
    final TextStyle dataColumnStyle = TextStyle(fontWeight: FontWeight.bold);
    return FutureBuilder<List<models.Deck>>(
      future: decksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(),
          );
        } else {
          final List<models.Deck>? decks = snapshot.data;
          return Scaffold(
            appBar: AppBar(title: Text("My Decks")),
            drawer: MainMenuDrawer(),
            body: ListView(
              children: [
                DataTable(columns: [
                  DataColumn(
                      label: Text("Deck Name", style: dataColumnStyle)),
                  DataColumn(
                      label: Text("Colors", style: dataColumnStyle)),
                  DataColumn(
                      label: Text("Date", style: dataColumnStyle)),
                ], rows: [
                  ...generateDataRows(decks, context)
                ])
              ],
            )
          );
        }
      });
  }

  List<DataRow> generateDataRows(List<models.Deck>? decks, context) {
    final TextStyle dateColumnStyle = TextStyle(
        color: Colors.grey.withAlpha(255), fontStyle: FontStyle.italic);

    var dataRowList = decks?.map((deck) {
      return DataRow(cells: [
        DataCell(
          Text(deck.name),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DeckViewer(deckId: deck.id)));
          },
        ),
        DataCell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DeckViewer(deckId: deck.id)));
          },
          Row(
            children: [
              for (String color in deck.colors.split(""))
                SvgPicture.asset(
                  "assets/svg_icons/$color.svg",
                  height: 14,
                )
            ],
          )
        ),
        DataCell(
          Text(convertDatetimeToYMDHM(deck.dateTime),
          style: dateColumnStyle),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DeckViewer(deckId: deck.id)));
          },
        )
      ]);
    }).toList();
    if (dataRowList != null) {
      return dataRowList;
    } else {
      return [];
    }
  }
}