import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '/utils/utils.dart';
import '/utils/data.dart';
import '/utils/models.dart';
import '/widgets/deck_viewer.dart';
import '/widgets/main_menu_drawer.dart';

DeckStorage _deckStorage = DeckStorage();

TextStyle _headerStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold
);

class MyDecksOverview extends StatefulWidget {
  const MyDecksOverview({super.key});

  @override
  MyDecksOverviewState createState() => MyDecksOverviewState();
}

class MyDecksOverviewState extends State<MyDecksOverview> {
  late Future<List<Deck>> decksFuture;
  late Future<List<Set>> setsFuture;

  @override
  void initState() {
    super.initState();
    _deckStorage.init();
    decksFuture = _deckStorage.getAllDecks();
    setsFuture = _deckStorage.getAllSets();
  }

  void refreshDecks() {
    setState(() {
      decksFuture = _deckStorage.getAllDecks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("My Decks")),
      drawer: MainMenuDrawer(),
      body: FutureBuilder(
        future: Future.wait([decksFuture, setsFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator());
          } else {
            // Getting state
            final decks = snapshot.data![0] as List<Deck>;
            final sets = snapshot.data![1] as List<Set>;
            final setsMap = {for (Set set in sets) set.code: set.name};

            // View constructor
            return ListView.separated(
              itemCount: decks.length,
              separatorBuilder: (context, index) => Divider(indent: 20, endIndent: 20, color: Colors.white12),
              itemBuilder: (context, index) {
                return Slidable(
                  startActionPane: ActionPane(
                    extentRatio: 0.3,
                    motion: BehindMotion(),
                    children: [SlidableAction(
                      label: "Edit",
                      icon: Icons.edit_rounded,
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      onPressed: (_) {
                        showDialog(
                          context: context,
                          builder: (_) => createEditDialog(decks[index], sets),
                        );
                      },
                    )]
                  ),
                  endActionPane: ActionPane(
                    extentRatio: 0.3,
                    motion: ScrollMotion(),
                    children: [SlidableAction(
                      label: "Delete",
                      icon: Icons.delete_rounded,
                      backgroundColor: Colors.red,
                      onPressed: (_) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('Confirmation'),
                            content: Text('Are you sure you want to delete this deck?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text("Cancel")
                              ),
                              TextButton(
                                onPressed: () {
                                  _deckStorage.deleteDeck(decks[index].id);
                                  refreshDecks();
                                  Navigator.of(context).pop();
                                },
                                child: Text("Delete")
                              )
                            ],
                          ),
                        );
                      }
                    )]
                  ),
                  child: ListTile(
                    leading: deckColorsWidget(decks[index]),
                    title: Text(
                      decks[index].setId != null ? "Draft: ${setsMap[decks[index].setId]}" : "Draft Deck ${index + 1}",
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(Icons.keyboard_arrow_right_rounded, size: 25,),
                    subtitle: Text(
                        "W/L: ${decks[index].winLoss ?? '-'}  |  Set: ${decks[index].setId != null ? decks[index].setId!.toUpperCase() :  '-' }  |  ${convertDatetimeToYMD(decks[index].dateTime)}",
                        overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => DeckViewer(deckId: decks[index].id)
                    )).then((_) => refreshDecks()),
                  )
                );
              },
            );
          }
        }
      )
    );
  }

  Widget createEditDialog(Deck deck, List<Set> sets) {

    final winLossController = TextEditingController(text: deck.winLoss);
    final dateTimeController = TextEditingController(text: convertDatetimeToYMDHM(deck.dateTime));
    final _formKey = GlobalKey<FormState>();
    String? currentSetId = deck.setId;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 24),
      title: Text('Edit'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Win / Loss:", style: _headerStyle),
            TextFormField(
              controller: winLossController,
              decoration: InputDecoration(border: OutlineInputBorder()),
              autovalidateMode: AutovalidateMode.always,
              validator: (value) {
                return regexValidator(value!, r'^\d/\d$')
                    ? "Must be {W}/{L} format"
                    : null;
              },
            ),
            Text("Set:", style: _headerStyle),
            DropdownMenu(
              initialSelection: currentSetId,
              dropdownMenuEntries: (sets
                ..sort((a, b) => (a.name.toString().compareTo(b.name.toString()))))
                  .map((set) => DropdownMenuEntry(value: set.code, label: set.name)).toList(),
              onSelected: (value) {
                currentSetId = value;
              },
            ),
            Text("Date Time:", style: _headerStyle),
            TextFormField(
              controller: dateTimeController,
              autovalidateMode: AutovalidateMode.always,
              decoration: InputDecoration(border: OutlineInputBorder()),
              validator: (value) {
                return regexValidator(value!, r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')
                    ? "Must be YYYY/MM/DD HH:MM"
                    : null;
              },
            )
          ],
        )
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Dismiss")
        ),
        TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Since this is an existing deck_id, it should overwrite
                // metadata in db.
                final dt = DateTime.parse(dateTimeController.text);
                _deckStorage.insertDeck({
                  'id': deck.id,
                  'win_loss': winLossController.text,
                  'set_id': currentSetId,
                  'datetime': dt.toIso8601String()});
                refreshDecks();
                Navigator.of(context).pop();
              }
            },
            child: Text("Save")
        )
      ],
    );
  }

  Widget deckColorsWidget (Deck deck) {
    int numColors = deck.colors.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: numColors*15),
      child: Row(
        children: [
          for (String color in deck.colors.split(""))
            SvgPicture.asset(
              "assets/svg_icons/$color.svg",
              height: 14,
            )
        ],
      )
    );
  }
}