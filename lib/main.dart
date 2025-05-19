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

  final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.deepPurpleAccent,
    focusColor: Colors.deepPurpleAccent,
    highlightColor: Colors.green
  );

  final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.deepPurple,
    focusColor: Colors.blueAccent,
    highlightColor: Colors.lightGreen
  );

  runApp(
    MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: MyDecksOverview(),
      navigatorObservers: [routeObserver],
    ),
  );
}
