import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;

import '/utils/data.dart';
import '/utils/models.dart';
import '/screens/settings/download_screen.dart';
import '/widgets/card_statistics.dart';

class StatisticsLauncher extends StatefulWidget {
  const StatisticsLauncher({super.key});

  @override
  StatisticsLauncherState createState() => StatisticsLauncherState();
}

class StatisticsLauncherState extends State<StatisticsLauncher> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
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
  void dispose() {
    super.dispose();
  }

  // Ensure widgets keeps state when changing tab
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

                List<Cube> playedCubesList = decks
                    .map((deck) => deck.cubecobraId)
                    .where((cubeId) => cubeId != null)
                    .map((cubeId) => cubes.firstWhere((cube) => cube.cubecobraId == cubeId))
                    .toSet().toList();
                List<Set> playedSetsList = decks
                    .map((deck) => deck.setId)
                    .where((setId) => setId != null)
                    .map((setId) => sets.firstWhere((set) => set.code == setId))
                    .toSet().toList();

                int countCubeDecks(String cubeId) {
                  return decks
                      .where((deck) => deck.cubecobraId != null)
                      .where((deck) => deck.cubecobraId == cubeId)
                      .fold(0, (previousValue, element) => previousValue + 1);
                }

                int countSetDecks(String setId) {
                  return decks
                      .where((deck) => deck.setId != null)
                      .where((deck) => deck.setId == setId)
                      .fold(0, (previousValue, element) => previousValue + 1);
                }

                widget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(15, 25, 0, 5),
                      child: Text(
                        "My Cubes",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline
                        ),
                      )
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: playedCubesList.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(playedCubesList[index].name),
                        subtitle: Text(
                          "Decks: ${countCubeDecks(playedCubesList[index].cubecobraId)}"
                        ),
                        trailing: Icon(Icons.keyboard_arrow_right_rounded, size: 25),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => CardStatistics(cube: playedCubesList[index])),
                        )
                      ),
                    ),
                    Container(
                        padding: EdgeInsets.fromLTRB(15, 20, 0, 5),
                        child: Text(
                          "My Sets",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline
                          ),
                        )
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: playedSetsList.length,
                      physics: NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) => ListTile(
                        title: Text(playedSetsList[index].name),
                        subtitle: Text(
                            "Decks: ${countSetDecks(playedSetsList[index].code)}"
                        ),
                        trailing: Icon(Icons.keyboard_arrow_right_rounded, size: 25),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => CardStatistics(set: playedSetsList[index])),
                        )
                      ),
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
}
