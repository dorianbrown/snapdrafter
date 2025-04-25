import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/utils/data.dart';
import 'screens/decks_overview.dart';
import '/utils/route_observer.dart';

import 'package:flutter/scheduler.dart' show timeDilation;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize DeckStorage to have it available in future
  DeckStorage deckStorage = DeckStorage();
  await deckStorage.init();

  // Useful for debugging animations
  // TODO: Remove after polishing animations
  timeDilation = 1.0;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MyDecksOverview(),
      navigatorObservers: [routeObserver],
    ),
  );
}
