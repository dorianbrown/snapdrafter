import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/utils/data.dart';
import '/widgets/decks_overview.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  DeckStorage deckStorage = DeckStorage();
  await deckStorage.init();

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MyDecksOverview(),
    ),
  );
}
