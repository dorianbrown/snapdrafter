import 'package:flutter/material.dart' hide Card;

import '/utils/data.dart';
import '/utils/models.dart';
import '/utils/utils.dart';
import 'download_screen.dart';

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
              leading: Icon(Icons.sd_storage),
              subtitle: Text("Manage your local scryfall database", style: TextStyle(color: Colors.white38),),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DownloadScreen()),
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

class CubeSettings extends StatefulWidget {
  const CubeSettings({Key? key}) : super(key: key);

  @override
  State<CubeSettings> createState() => _CubeSettingsState();
}

class _CubeSettingsState extends State<CubeSettings> {
  late DeckStorage deckStorage;

  @override
  initState() {
    super.initState();
    deckStorage = DeckStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Cube Settings')),
        body: Container(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: ListView(
              children: [
                ListTile(
                  title: Text("My Cubes", style: TextStyle(decoration: TextDecoration.underline))
                ),
                ListTile(
                  title: Text("1. Premodern Plus Cube"),
                  tileColor: Colors.white12,
                  dense: true
                ),
                ListTile(
                  title: Text("2. Degenerate Micro Cube"),
                  tileColor: Colors.white12,
                  dense: true
                ),
                SizedBox(height: 20,),
                ListTile(
                  title: Text("Add a Cube"),
                  leading: Icon(Icons.add),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) {

                        List<Card> cubeList = [];
                        TextEditingController nameController = TextEditingController();
                        TextEditingController cubeListController = TextEditingController();
                        TextEditingController cubecobraIdController = TextEditingController();

                        return AlertDialog(
                            title: Text("Add a Cube"),
                            content: StatefulBuilder(
                                builder: (context, setState) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        controller: nameController,
                                        decoration: InputDecoration(hintText: "Cube Name")
                                      ),
                                      TextFormField(
                                          controller: cubecobraIdController,
                                          decoration: InputDecoration(hintText: "Cubecobra ID")
                                      ),
                                      SizedBox(
                                        height: 300,
                                        child: TextFormField(
                                          readOnly: true,
                                          expands: true,
                                          keyboardType: TextInputType.multiline,
                                          maxLines: null,
                                          minLines: null,
                                          controller: cubeListController,
                                        ),
                                      ),
                                      if (cubeList.isNotEmpty)
                                        Text("Cube cards found: ${cubeList.length}"),
                                      Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () async {
                                              String cubecobraId = cubecobraIdController.text;
                                              cubeList = await fetchCubecobraList(cubecobraId);
                                              String textList = (cubeList
                                                  .map((card) => card.name)
                                                  .toList()..sort())
                                                  .join("\n");
                                              setState(() {
                                                cubeListController.text = textList;
                                              });
                                            },
                                            child: Text("Get List")
                                          )
                                        ],
                                      )
                                    ],
                                  );
                                }
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text("Close")
                              ),
                              TextButton(
                                  onPressed: () {
                                    String name = nameController.text;
                                    String ymd = convertDatetimeToYMD(DateTime.now());
                                    String cubecobraId = cubecobraIdController.text;
                                    deckStorage.saveNewCube(name, ymd, cubecobraId, cubeList);
                                    Navigator.of(context).pop();
                                  },
                                  child: Text("Save")
                              )
                            ]
                        );
                      }
                    );
                  },
                )
              ],
            )
        )
    );
  }
}