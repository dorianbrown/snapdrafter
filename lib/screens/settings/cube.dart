import 'package:flutter/material.dart' hide Card;

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/data/models/cube.dart';
import '/data/models/card.dart';
import '/data/repositories/cube_repository.dart';

class CubeSettings extends StatefulWidget {
  const CubeSettings({Key? key}) : super(key: key);

  @override
  State<CubeSettings> createState() => _CubeSettingsState();
}

class _CubeSettingsState extends State<CubeSettings> {
  late CubeRepository cubeRepository;

  final DeckChangeNotifier _notifier = DeckChangeNotifier();

  @override
  initState() {
    super.initState();
    cubeRepository = CubeRepository();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Cube Settings')),
        body: Container(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Text("My Cubes"),
                FutureBuilder(
                  future: cubeRepository.getAllCubes(),
                  builder: (futureContext, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return CircularProgressIndicator();
                    }
                    else {
                      final cubes = snapshot.data as List<Cube>;
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: cubes.length,
                        itemBuilder: (listBuilderContext, index) {
                          return ListTile(
                            title: Text(cubes[index].name),
                            subtitle: Text(cubes[index].ymd),
                            trailing: IconButton(
                                onPressed: () async {
                                  await cubeRepository.deleteCube(cubes[index].cubecobraId);
                                  setState(() {});
                                },
                                icon: Icon(Icons.delete)
                            ),
                            tileColor: Colors.white12,
                          );
                        },
                      );
                    }
                  },
                ),
                ListView(
                  shrinkWrap: true,
                  children: [
                    generateAddCubeListTile()
                  ],
                )
              ],
            )
        )
    );
  }

  ListTile generateAddCubeListTile() {
    return ListTile(
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
                            TextFormField(
                              readOnly: true,
                              keyboardType: TextInputType.multiline,
                              maxLines: 10,
                              minLines: 1,
                              controller: cubeListController,
                            ),
                            if (cubeList.isNotEmpty)
                              Text("Cube cards found: ${cubeList.length}"),
                            SizedBox(height: 10,),
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
                          cubeRepository.saveNewCube(name, ymd, cubecobraId, cubeList);
                          _notifier.markNeedsRefresh();
                          Navigator.of(context).pop();
                          setState(() {});
                        },
                        child: Text("Save")
                    )
                  ]
              );
            }
        );
      },
    );
  }
}