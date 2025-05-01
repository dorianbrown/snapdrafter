import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/utils/data.dart';
import 'screens/decks_overview.dart';
import '/utils/route_observer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize DeckStorage to have it available in future
  DeckStorage deckStorage = DeckStorage();
  await deckStorage.init();

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MyDecksOverview(),
      navigatorObservers: [routeObserver],
    ),
  );
}
