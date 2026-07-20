import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:shared_preferences/shared_preferences.dart';

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/data/models/cube.dart';
import '/data/models/card.dart';
import '/data/models/cubecobra_config.dart';
import '/data/repositories/cube_repository.dart';
import '/services/cubecobra_api.dart';

class CubeSettings extends StatefulWidget {
  const CubeSettings({super.key});

  @override
  State<CubeSettings> createState() => _CubeSettingsState();
}

class _CubeSettingsState extends State<CubeSettings> {
  late CubeRepository cubeRepository;
  late SharedPreferences _prefs;

  final DeckChangeNotifier _notifier = DeckChangeNotifier();
  final Map<String, CubeCobraCredentials?> _ccAuth = {};

  @override
  initState() {
    super.initState();
    cubeRepository = CubeRepository();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCubecobraAuth();
  }

  Future<void> _loadCubecobraAuth() async {
    final cubes = await cubeRepository.getAllCubes();
    for (final cube in cubes) {
      final json = _prefs.getString('cc_auth_${cube.cubecobraId}');
      if (json != null) {
        try {
          _ccAuth[cube.cubecobraId] = CubeCobraCredentials.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          );
        } catch (_) {
          _ccAuth[cube.cubecobraId] = null;
        }
      } else {
        _ccAuth[cube.cubecobraId] = null;
      }
    }
    if (mounted) setState(() {});
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
                          final cube = cubes[index];
                          final signedIn = _ccAuth[cube.cubecobraId] != null;
                          return ListTile(
                            title: Text(cube.name),
                            subtitle: Text(
                              signedIn
                                  ? 'Signed in to CubeCobra'
                                  : cube.ymd,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (signedIn)
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                IconButton(
                                    onPressed: () async {
                                      await cubeRepository.deleteCube(cube.cubecobraId);
                                      setState(() {});
                                    },
                                    icon: Icon(Icons.delete)
                                ),
                              ],
                            ),
                            tileColor: Colors.white12,
                            onLongPress: () => _showCubecobraAuthDialog(
                              cube.cubecobraId,
                              cube.name,
                            ),
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

  void _showCubecobraAuthDialog(String cubecobraId, String cubeName) {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final existing = _ccAuth[cubecobraId];
    if (existing != null) {
      usernameCtrl.text = existing.username;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        bool signingIn = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('CubeCobra Sign In'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sign in to CubeCobra for $cubeName.'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      await _prefs.remove('cc_auth_$cubecobraId');
                      _ccAuth.remove(cubecobraId);
                      setState(() {});
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('Sign Out'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: signingIn
                      ? null
                      : () async {
                          final username = usernameCtrl.text.trim();
                          final password = passwordCtrl.text;
                          if (username.isEmpty || password.isEmpty) return;

                          setDialogState(() => signingIn = true);

                          try {
                            final cookie = await login(username, password);
                            final creds = CubeCobraCredentials(
                              cubeId: cubecobraId,
                              username: username,
                              cookie: cookie,
                            );
                            await _prefs.setString(
                              'cc_auth_$cubecobraId',
                              jsonEncode(creds.toJson()),
                            );
                            _ccAuth[cubecobraId] = creds;
                            setState(() {});
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          } on CubeCobraApiException catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Sign in failed: $e')),
                              );
                            }
                          } finally {
                            if (ctx.mounted) {
                              setDialogState(() => signingIn = false);
                            }
                          }
                        },
                  child: signingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(existing != null ? 'Re-Sign In' : 'Sign In'),
                ),
              ],
            );
          },
        );
      },
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
                                decoration: InputDecoration(
                                  hintText: "Cubecobra ID",
                                  helperText: "Used for draft record submissions",
                                )
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