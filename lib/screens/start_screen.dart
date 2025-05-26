import 'dart:async';

import 'package:flutter/material.dart' hide Card, Orientation;
import 'package:shared_preferences/shared_preferences.dart';

import '/widgets/decks_overview.dart';
import '/widgets/statistics_launcher.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  StartScreenState createState() => StartScreenState();
}

class StartScreenState extends State<StartScreen> with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Creating tab controller
    _tabController = TabController(length: 2, vsync: this);
    // Adding first launch popup callback
    WidgetsBinding.instance.addPostFrameCallback((_) => launchWelcomeDialog());
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SnapDrafter"),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(child: Text("My Decks")),
            Tab(child: Text("Statistics")),
          ]
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: NeverScrollableScrollPhysics(),
        children: [
          MyDecksOverview(),
          StatisticsLauncher()
        ]
      )
    );
  }

  Future launchWelcomeDialog() async {

    final prefs = await SharedPreferences.getInstance();
    bool hasSeenWelcomePopup = prefs.getBool("welcome_popup_seen") ?? false;

    if (!hasSeenWelcomePopup) {

      prefs.setBool("welcome_popup_seen", true);

      TextStyle titleStyle = TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold
      );
      double paragraphBreak = 4;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              SizedBox(height: paragraphBreak,),
              Text("Welcome to the Open Beta!", style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold
              )),
              SizedBox(height: paragraphBreak,),
              Text("Thanks for being "
                  "one of the first to try out our app and help make it great."
                  " As a beta tester, you're getting an early preview. This"
                  " means you might encounter some bugs or see features that"
                  " are still being polished. "),
              SizedBox(height: paragraphBreak,),
              Text("Feedback", style: titleStyle,),
              Text("In case you find a bug, have ideas for how things could "
                "be improved, or features that are missing, I'd love to hear "
                  "your feedback."),
              Text("Look for the 'Private feedback to developer' section in the "
                  "app's Play Store page."),
              SizedBox(height: paragraphBreak,),
              Text("Getting Started", style: titleStyle,),
              Text("I try to make the interface as intuitive as possible, but "
                  "if can't figure something out, you can find some additional "
                  "information in 'Settings > Help'."),
              SizedBox(height: paragraphBreak,),
              Text("Support", style: titleStyle,),
              Text("My aim is to keep SnapDrafter free, ad-free, and available"
                  " to as many cube-lovers as possible. Donations make that "
                  "possible."),
              Text("You can find links in 'Settings > Donations'.")
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text("Close")
            ),
          ],
        ),
      );
    }
  }

}
