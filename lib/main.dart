import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/utils/data.dart';
import '/widgets/decks_overview.dart';
import '/widgets/deck_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  DeckStorage _deckStorage = DeckStorage();
  await _deckStorage.init();

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MyDecksOverview(),
    ),
  );
}
