import 'package:flutter/material.dart' hide Card;

import '/utils/data.dart';
import '/utils/models.dart';
import '/utils/utils.dart';

class BackupSettings extends StatefulWidget {
  const BackupSettings({Key? key}) : super(key: key);

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  late DeckStorage deckStorage;

  @override
  initState() {
    super.initState();
    deckStorage = DeckStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Backup Settings')),
        body: Container(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                FutureBuilder(
                  future: deckStorage.getAllDecks(),
                  builder: (futureContext, snapshot) {
                    // FIXME: Currently crashing when loading
                    if (snapshot.connectionState != ConnectionState.done) {
                      return CircularProgressIndicator();
                    }
                    else {
                      final decks = snapshot.data as List<Deck>;
                      return Text("Current decks: ${decks.length}", style: TextStyle(fontSize: 18),);
                    }
                  },
                ),
                Divider(),
                ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text("Backup Data to File"),
                      subtitle: Text("A file will be saved to your Downloads folder"),
                      leading: Icon(Icons.sd_card),
                      onTap: () {}
                    ),
                    ListTile(
                        title: Text("Restore from Backup"),
                        leading: Icon(Icons.file_open_rounded),
                        onTap: () {}
                    )
                  ],
                )
              ],
            )
        )
    );
  }
}