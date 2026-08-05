import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:snapdrafter/utils/utils.dart';

import '/data/database/database_helper.dart';
import '/data/repositories/card_repository.dart';
import '/data/repositories/set_repository.dart';
import '/screens/decks_overview.dart';
import '/screens/image_processing_screen.dart';
import '/screens/settings/download_screen.dart';
import '/services/draft/draft_session_notifier.dart';
import '/services/draft/notification_service.dart';
import '/utils/release_date_helper.dart';
import '/utils/theme_notifier.dart';
import '/utils/themes.dart';
import '/widgets/update_prompt_dialog.dart';

import 'dart:math';

import 'package:universal_ble/universal_ble.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // enable logging for bluetooth
  await UniversalBle.setLogLevel(BleLogLevel.verbose);

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

  String deviceId = prefs.getString('device_id') ?? _generateDeviceId();
  await prefs.setString('device_id', deviceId);

  await NotificationService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeNotifier),
        ChangeNotifierProvider(
          create: (_) => DraftSessionNotifier(myDeviceId: deviceId),
        ),
      ],
      child: MainApp(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> with WidgetsBindingObserver {
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final ReleaseDateHelper _releaseDateHelper = ReleaseDateHelper();
  late SetRepository _setRepository;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setRepository = SetRepository();
    
    // Run the release date check after the app is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _waitForWelcomeDismissed();
      await _checkForNewReleases();
    });

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          addShareIntentCallback(sharedFile);
        });
      }
    });
  }

  void addShareIntentCallback(String imagePath) async {
    await Future.delayed(Duration(milliseconds: 100));

    if (mounted && navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => deckImageProcessing(
                filePath: imagePath,
                captureSource: CaptureSource.share,
              ),
        ),
        ModalRoute.withName('/'),
      );
    }
  }
  
  Future<void> _waitForWelcomeDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    while (!(prefs.getBool("welcome_popup_seen") ?? false)) {
      await Future.delayed(Duration(milliseconds: 500));
      await prefs.reload();
    }
  }

  Future<void> _checkForNewReleases() async {
    try {
      final cardRepo = CardRepository();
      if (await cardRepo.isCardTableEmpty() && mounted) {
        _showUpdatePrompt([], isInitialDownload: true);
        return;
      }

      // Check upcoming releases
      if (await _releaseDateHelper.shouldFetchNewDates()) {
        final newDates = await _setRepository.fetchUpcomingReleaseDates();
        await _releaseDateHelper.saveUpcomingReleaseDates(newDates);
      }

      final upcomingDates = await _releaseDateHelper.getUpcomingReleaseDates();
      final promptedSets = await _releaseDateHelper.getPromptedSets();
      final now = DateTime.now();

      final upcomingToPrompt = upcomingDates.entries
          .where((entry) =>
              DateTime.parse(entry.value["date"]!)
                  .subtract(Duration(
                      days:
                          SetRepository.releaseNoticeDays -
                          SetRepository.prereleaseWindowDays))
                  .isBefore(now) &&
              !promptedSets.contains(entry.key))
          .map((entry) => {"code": entry.key, "name": entry.value["name"]!})
          .toList();

      // Check for missing released sets not in local database
      final missingSets = await _setRepository.getMissingReleasedSets();
      final promptedMissing = await _releaseDateHelper.getPromptedMissingSets();
      final missingToPrompt = missingSets
          .where((s) => !promptedMissing.contains(s['code']!))
          .toList();

      final allSetsToPrompt = [...upcomingToPrompt, ...missingToPrompt];

      if (allSetsToPrompt.isNotEmpty && mounted) {
        _showUpdatePrompt(allSetsToPrompt);

        // Mark all as prompted
        for (final entry in upcomingToPrompt) {
          await _releaseDateHelper.addToPromptedDates(entry["code"]!);
        }
        if (missingToPrompt.isNotEmpty) {
          await _releaseDateHelper.addToPromptedMissingSets(
            missingToPrompt.map((s) => s['code']!).toSet(),
          );
        }
      }
    } catch (e) {
      // Don't block app if there's an error
      debugPrint('Error checking for new releases: $e');
    }
  }
  
  void _showUpdatePrompt(List<Map<String, String>> sets, {bool isInitialDownload = false}) {
    if (navigatorKey.currentState == null) return;

    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => UpdatePromptDialog(
        sets: sets,
        isInitialDownload: isInitialDownload,
        onUpdateNow: () {
          // Navigate to download screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DownloadScreen(),
            ),
          );
        },
        onRemindLater: () {
          // User chose to be reminded later
          // Could schedule a reminder for tomorrow
          // For now, just close the dialog
        },
      ),
    );
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.instance.lifecycleState = state;
  }
}

final _randomDevice = Random();

String _generateDeviceId() {
  final chars = 'abcdef0123456789';
  String hex(int len) => List.generate(
        len,
        (_) => chars[_randomDevice.nextInt(chars.length)],
      ).join();
  return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
}
