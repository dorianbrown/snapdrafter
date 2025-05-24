import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;

import '/utils/data.dart';
import '/utils/models.dart';

class CardStatistics extends StatefulWidget {
  final Set? set;
  final Cube? cube;
  const CardStatistics({super.key, this.set, this.cube});

  @override
  CardStatisticsState createState() => CardStatisticsState(set, cube);
}

class CardStatisticsState extends State<CardStatistics> {
  final Set? set;
  final Cube? cube;
  CardStatisticsState(this.set, this.cube);

  late Future<List<Deck>> decksFuture;
  late Future<List<Set>> setsFuture;
  late Future<List<Cube>> cubesFuture;
  late Future buildFuture;
  late DeckStorage _deckStorage;

  @override
  void initState() {
    super.initState();
    // Retrieving deck/set/cube data
    _deckStorage = DeckStorage();
    decksFuture = _deckStorage.getAllDecks();
    setsFuture = _deckStorage.getAllSets();
    cubesFuture = _deckStorage.getAllCubes();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    String name = (set != null)
        ? set!.name
        : cube!.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
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

              List<Deck> statsDecks = (set != null)
                  ? decks.where((deck) => deck.setId != null)
                    .where((deck) => deck.setId == set!.code)
                    .toList()
                  : decks.where((deck) => deck.cubecobraId != null)
                    .where((deck) => deck.cubecobraId == cube!.cubecobraId)
                    .toList();

              widget = Text("Placeholder");

            }
            return AnimatedSwitcher(
                duration: Duration(milliseconds: 500),
                child: widget
            );
          }
      )
    );
  }
}
