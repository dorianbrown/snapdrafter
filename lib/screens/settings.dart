import 'package:flutter/material.dart' hide Card;
import 'package:package_info_plus/package_info_plus.dart';

import 'settings/download_screen.dart';
import 'settings/cube.dart';
import 'settings/backup.dart';
import 'settings/user.dart';
import 'settings/help.dart';
import 'settings/donations.dart';

class Settings extends StatefulWidget {
  const Settings({Key? key}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {

  late PackageInfo _packageInfo;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: ListView(
          children: [
            ListTile(
              title: Text("Cubes"),
              leading: Icon(Icons.view_in_ar),
              subtitle: Text("Manage your cubes", style: TextStyle(color: Colors.white38),),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CubeSettings()),
                );
              },
            ),
            ListTile(
              title: Text("Scryfall"),
              leading: Icon(Icons.download),
              subtitle: Text("Manage your local scryfall database", style: TextStyle(color: Colors.white38),),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DownloadScreen()),
                );
              },
            ),
            ListTile(
              title: Text("Backup / Restore"),
              leading: Icon(Icons.sd_card),
              subtitle: Text("Save decks to local storage", style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BackupSettings()),
                );
              },
            ),
            ListTile(
              title: Text("User Name"),
              leading: Icon(Icons.person),
              subtitle: Text("Details for sharing decklists", style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UserSettings()),
                );
              },
            ),
            ListTile(
              title: Text("Help"),
              leading: Icon(Icons.question_mark),
              subtitle: Text("Useful information about using this app", style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HelpScreen()),
                );
              },
            ),
            ListTile(
              title: Text("Donations"),
              leading: Icon(Icons.monetization_on, color: Colors.lightGreen),
              subtitle: Text("Donate and support the development of this app", style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DonationScreen()),
                );
              },
            ),
            ListTile(
              title: Text("About"),
              leading: Icon(Icons.info),
              subtitle: Text("Information about the app", style: TextStyle(color: Colors.white38)),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationIcon: Icon(Icons.info),
                  applicationName: "SnapDrafter",
                  applicationVersion: _packageInfo.version,
                  applicationLegalese: "© Copyright Dorian Brown 2025",
                );
              }
            ),
          ],
        )
      )
    );
  }
}