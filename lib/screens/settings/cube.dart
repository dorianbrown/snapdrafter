import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/utils/utils.dart';
import '/data/models/cube.dart';
import '/data/models/card.dart' as mtg;
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

  List<Cube> _cubes = [];
  bool _cubesLoading = true;
  final Map<String, CubeCobraCredentials?> _ccAuth = {};
  bool _debugEnabled = false;

  @override
  initState() {
    super.initState();
    cubeRepository = CubeRepository();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _debugEnabled = _prefs.getBool("debug_enabled") ?? false;
    await _refreshCubes();
  }

  Future<void> _refreshCubes() async {
    final cubes = await cubeRepository.getAllCubes();
    await _loadAuth(cubes);
    if (mounted) {
      setState(() {
        _cubes = cubes;
        _cubesLoading = false;
      });
    }
  }

  Future<void> _loadAuth(List<Cube> cubes) async {
    _ccAuth.clear();
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cube Settings')),
      body: _cubesLoading
          ? const Center(child: CircularProgressIndicator())
          : _cubes.isEmpty
              ? _buildEmptyState()
              : _buildCubeList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCubeDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Cube'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No cubes added yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a cube to enable CubeCobra draft record submissions.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCubeList() {
    return RefreshIndicator(
      onRefresh: _refreshCubes,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _cubes.length,
        itemBuilder: (context, index) {
          final cube = _cubes[index];
          final signedIn = _ccAuth[cube.cubecobraId] != null;
          return _buildCubeCard(cube, signedIn);
        },
      ),
    );
  }

  Widget _buildCubeCard(Cube cube, bool signedIn) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCubeOptions(cube, signedIn),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cube.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _buildAuthChip(cube, signedIn),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _confirmDeleteCube(cube),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete cube',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    cube.cubecobraId,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.style_outlined, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '${cube.cards.length} cards',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthChip(Cube cube, bool signedIn) {
    if (signedIn) {
      return GestureDetector(
        onTap: () => _showCubeOptions(cube, true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text(
                'Signed in',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_debugEnabled) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => _showAuthDialog(cube.cubecobraId, cube.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'Sign in',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  void _showCubeOptions(Cube cube, bool signedIn) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  cube.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${cube.cubecobraId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${cube.cards.length} cards · Added ${cube.ymd}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                if (signedIn) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showAuthDialog(cube.cubecobraId, cube.name);
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Re-sign in'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _prefs.remove('cc_auth_${cube.cubecobraId}');
                      _ccAuth.remove(cube.cubecobraId);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      setState(() {});
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ] else if (_debugEnabled) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showAuthDialog(cube.cubecobraId, cube.name);
                    },
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Sign in to CubeCobra'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _confirmDeleteCube(cube);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete Cube'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteCube(Cube cube) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Cube'),
        content: Text('Remove "${cube.name}" and its card list? This will not affect any CubeCobra records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await cubeRepository.deleteCube(cube.cubecobraId);
              await _prefs.remove('cc_auth_${cube.cubecobraId}');
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _refreshCubes();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAuthDialog(String cubecobraId, String cubeName) {
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
              title: const Text('CubeCobra Sign In'),
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

                            final authResult = await validateCubeAuth(cubecobraId, cookie);

                            if (authResult == CubeAuthResult.notOwner) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'You do not own this cube. Only the cube owner can submit draft records.',
                                    ),
                                  ),
                                );
                              }
                              setDialogState(() => signingIn = false);
                              return;
                            }

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
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            setState(() {});
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

  void _showAddCubeDialog() {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    List<mtg.Card>? cubeCards;
    bool fetching = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add Cube'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CubeCobra ID',
                      hintText: 'e.g. premodernplus',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  if (cubeCards == null)
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: fetching
                            ? null
                            : () async {
                                final id = idCtrl.text.trim();
                                if (id.isEmpty) return;

                                setDialogState(() {
                                  fetching = true;
                                  error = null;
                                });

                                try {
                                  final data = await fetchCubecobraCube(id);
                                  cubeCards = data.cards;
                                  nameCtrl.text = data.name;
                                } catch (e) {
                                  error = '$e';
                                }

                                setDialogState(() => fetching = false);
                              },
                        icon: fetching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download, size: 18),
                        label: Text(fetching ? 'Loading...' : 'Fetch Cube'),
                      ),
                    ),
                  if (cubeCards != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Text(
                          '${cubeCards!.length} cards found',
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cube Name',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                if (cubeCards != null)
                  FilledButton(
                    onPressed: () {
                      final id = idCtrl.text.trim();
                      final name = nameCtrl.text.trim().isNotEmpty
                          ? nameCtrl.text.trim()
                          : id;
                      final ymd = convertDatetimeToYMD(DateTime.now());
                      cubeRepository.saveNewCube(name, ymd, id, cubeCards!);
                      Navigator.of(ctx).pop();
                      _refreshCubes();
                    },
                    child: const Text('Save'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
