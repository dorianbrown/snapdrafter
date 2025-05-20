import 'package:flutter/material.dart' hide Card;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'settings/download_screen.dart';
import 'settings/cube.dart';
import 'settings/backup.dart';
import 'settings/user.dart';
import 'settings/help.dart';
import 'settings/donations.dart';
import '/utils/theme_notifier.dart';

class Settings extends StatefulWidget {
  const Settings({Key? key}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {

  late PackageInfo _packageInfo;
  ThemeMode currentThemeMode = ThemeMode.light;
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _getSharedPreferences();
  }

  Future<void> _initPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  Future<void> _getSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      currentThemeMode = switch (prefs.getString("theme")) {
        "light" => ThemeMode.light,
        "dark" => ThemeMode.dark,
        "auto" => ThemeMode.system,
        _ => ThemeMode.dark
      };
    });
  }

  @override
  Widget build(BuildContext context) {

    final TextStyle subtitleColor = TextStyle(
        color: Theme.of(context).hintColor
    );

    ThemeNotifier themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: ListView(
          children: [
            ListTile(
              title: Text("Cubes"),
              leading: Icon(Icons.view_in_ar),
              subtitle: Text("Manage your cubes", style: subtitleColor),
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
              subtitle: Text("Manage your local scryfall database", style: subtitleColor),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DownloadScreen()),
                );
              },
            ),
            ListTile(
              title: Text("Theme"),
              leading: Icon(Icons.settings_display),
              subtitle: Text(switch (currentThemeMode) {
                ThemeMode.light => "Light",
                ThemeMode.dark => "Dark",
                ThemeMode.system => "Auto"
              }, style: subtitleColor),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            RadioListTile(
                                title: Text("Light"),
                                value: ThemeMode.light,
                                groupValue: currentThemeMode,
                                onChanged: (val) {
                                  themeNotifier.setTheme(val!);
                                  prefs.setString("theme", "light");
                                  setState(() {
                                    currentThemeMode = val;
                                  });
                                }
                            ),
                            RadioListTile(
                                title: Text("Dark"),
                                value: ThemeMode.dark,
                                groupValue: currentThemeMode,
                                onChanged: (val) {
                                  themeNotifier.setTheme(val!);
                                  prefs.setString("theme", "dark");
                                  setState(() {
                                    currentThemeMode = val;
                                  });
                                }
                            ),
                            RadioListTile(
                                title: Text("Auto"),
                                value: ThemeMode.system,
                                groupValue: currentThemeMode,
                                onChanged: (val) {
                                  prefs.setString("theme", "auto");
                                  themeNotifier.setTheme(val!);
                                  setState(() {
                                    currentThemeMode = val;
                                  });
                                }
                            )
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text("Close")
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            ListTile(
              title: Text("Backup / Restore"),
              leading: Icon(Icons.sd_card),
              subtitle: Text("Save decks to local storage", style: subtitleColor),
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
              subtitle: Text("Details for sharing decklists", style: subtitleColor),
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
              subtitle: Text("Useful information about using this app", style: subtitleColor),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HelpScreen()),
                );
              },
            ),
            ListTile(
              title: Text("Donations"),
              leading: Icon(
                  Icons.monetization_on,
                  color: (ThemeMode.system == ThemeMode.light) ? Colors.green : Colors.lightGreen
              ),
              subtitle: Text("Donate and support the development of this app", style: subtitleColor),
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
              subtitle: Text("Information about the app", style: subtitleColor),
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