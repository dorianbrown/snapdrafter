import 'package:flutter/material.dart' hide Card;

import 'settings/download_screen.dart';
import 'settings/cube.dart';
import 'settings/backup.dart';

class Settings extends StatefulWidget {
  const Settings({Key? key}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {

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
              title: Text("Future options"),
              leading: Icon(Icons.build),
              subtitle: Text("Coming soon", style: TextStyle(color: Colors.white38)),
              enabled: false,
            ),
          ],
        )
      )
    );
  }
}