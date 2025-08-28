import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';

import '/data/database/database_helper.dart';
import '/screens/decks_overview.dart';
import '/screens/image_processing_screen.dart';
import '/utils/theme_notifier.dart';
import '/utils/themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Database to create/upgrade tables if necessary
  DatabaseHelper db = DatabaseHelper();
  await db.database;

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

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    _intentDataStreamSubscription = FlutterSharingIntent.instance.getMediaStream()
      .listen((List<SharedFile> val) {
        if (val.isNotEmpty) {
          final String sharedFile = val[0].value!;
          addShareIntentCallback(sharedFile);
        }
    });

    FlutterSharingIntent.instance.getInitialSharing().then((List<SharedFile> val) {
      if (val.isNotEmpty){
        final String sharedFile = val[0].value!;
        addShareIntentCallback(sharedFile);
      }
    });
  }

  void addShareIntentCallback(String imagePath) async {
    // Wait for the app to be fully built before navigating
    await Future.delayed(Duration(milliseconds: 100));

    if (mounted && navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => deckImageProcessing(filePath: imagePath),
        ),
        (route) => false, // Remove all previous routes
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          title: 'SnapDrafter',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeNotifier.themeMode,
          navigatorKey: navigatorKey,
          home: MyDecksOverview(),
        );
      },
    );
  }
}
