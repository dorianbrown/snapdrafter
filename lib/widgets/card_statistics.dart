import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:sqflite/sqflite.dart';

import '/utils/data.dart';
import '/utils/models.dart';
import '/utils/statistics.dart';

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
  late StatisticsRetriever statsRetriever;
  Future? futureCardWinRates;

  @override
  void initState() {
    super.initState();
    statsRetriever = StatisticsRetriever();
    statsRetriever.init().then((_) {
      futureCardWinRates = statsRetriever.getCardWinRates(
          cubeId: cube?.cubecobraId, setId: set?.code);
      futureCardWinRates!.then((_) {
        setState(() {});
      });
    });
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
          future: futureCardWinRates,
          builder: (context, snapshot) {
            Widget widget;
            if (snapshot.connectionState != ConnectionState.done || snapshot.data == null) {
              widget = Center(child: CircularProgressIndicator());
            } else {

              // Create card win rates
              List cardWinRates = snapshot.data;
              final columns = ["Name", "# Decks", "Win Rate"].map((el) =>
                DataColumn(
                  label: Expanded(
                    child: Text(
                      el,
                      style: TextStyle(fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    )
                  )
                )
              ).toList();

              final rows = cardWinRates.map((el) => DataRow(
                cells: [
                  DataCell(Text(el['name'].toString())),
                  DataCell(Text(el['num_decks'].toString())),
                  DataCell(Text(el['winrate'].toString())),
                ]
              )).toList();

              widget = SingleChildScrollView(
                child: DataTable(
                    columns: columns,
                    rows: rows
                ),
              );

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
