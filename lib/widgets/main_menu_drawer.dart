import 'package:flutter/material.dart';
import 'download_screen.dart';
import '/widgets/decks_overview.dart';

class MainMenuDrawer extends StatelessWidget {
  const MainMenuDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 120,
              child: DrawerHeader(
                decoration: BoxDecoration(color: Colors.blue),
                padding: EdgeInsets.fromLTRB(15, 40, 0, 0),
                child: Text('Decklist Scanner'),
              ),
            ),
            ListTile(
              title: const Text('Scan Deck'),
              onTap: () {
                Navigator.of(context).popUntil(ModalRoute.withName('/'));
              },
            ),
            ListTile(
              title: const Text('View My Decks'),
              onTap: () {
                Navigator.of(context).popUntil(ModalRoute.withName('/'));
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const MyDecksOverview()));
              },
            ),
            ListTile(
              title: const Text('Download Scryfall Data'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const DownloadScreen()));
              },
            )
          ],
        ));
  }
}