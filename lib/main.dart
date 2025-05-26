import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/utils/data.dart';
import 'screens/decks_overview.dart';
import '/utils/theme_notifier.dart';
import '/utils/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize DeckStorage to have it available in future
  DeckStorage deckStorage = DeckStorage();
  await deckStorage.init();

  // Get System Theme
  SharedPreferences prefs = await SharedPreferences.getInstance();
  ThemeMode currentTheme = switch (prefs.getString("theme")) {
    "light" => ThemeMode.light,
    "dark" => ThemeMode.dark,
    "auto" => ThemeMode.system,
    _ => ThemeMode.dark
  };
  final themeNotifier = ThemeNotifier();
  themeNotifier.setTheme(currentTheme);

  runApp(
    ChangeNotifierProvider(
      create: (_) => themeNotifier,
      child: MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          title: 'Flutter Theme Demo',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeNotifier.themeMode,
          home: MyDecksOverview(),
        );
      },
    );
  }
}
