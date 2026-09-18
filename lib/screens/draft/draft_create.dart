import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:universal_ble/universal_ble.dart';

import '../../data/models/cube.dart';
import '../../data/repositories/cube_repository.dart';
import '../../services/draft/draft_config.dart';
import '../../services/draft/draft_session_notifier.dart';

class DraftCreateScreen extends StatefulWidget {
  const DraftCreateScreen({super.key});

  @override
  State<DraftCreateScreen> createState() => _DraftCreateScreenState();
}

class _DraftCreateScreenState extends State<DraftCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _playerCtrl = TextEditingController();
  final _seatCtrl = TextEditingController(text: '8');
  final _roundMinCtrl = TextEditingController(text: '50');
  bool _creating = false;

  // Debug-only topology overrides (visible when debug mode is enabled).
  bool _debugEnabled = false;
  int _maxDirectLinks = DraftConfig.defaultMaxDirectLinks;
  int _relayMaxChildren = DraftConfig.defaultRelayMaxChildren;

  List<Cube> _cubes = [];
  String? _selectedCubecobraId;
  bool _cubesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    UniversalBlePeripheral.getCapabilities();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final cubes = await CubeRepository().getAllCubes();
    setState(() {
      _nameCtrl.text = '${prefs.getString("username") ?? "Player"}\'s Draft';
      _playerCtrl.text = prefs.getString("username") ?? '';
      _debugEnabled = prefs.getBool("debug_enabled") ?? false;
      _maxDirectLinks = DraftConfig.clampMaxDirectLinks(
        prefs.getInt(DraftConfig.prefMaxDirectLinks) ??
            DraftConfig.defaultMaxDirectLinks,
      );
      _relayMaxChildren = DraftConfig.clampRelayMaxChildren(
        prefs.getInt(DraftConfig.prefRelayMaxChildren) ??
            DraftConfig.defaultRelayMaxChildren,
      );
      _cubes = cubes;
      _cubesLoading = false;
    });
  }

  Future<void> _setMaxDirectLinks(int value) async {
    final clamped = DraftConfig.clampMaxDirectLinks(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(DraftConfig.prefMaxDirectLinks, clamped);
    if (mounted) setState(() => _maxDirectLinks = clamped);
  }

  Future<void> _setRelayMaxChildren(int value) async {
    final clamped = DraftConfig.clampRelayMaxChildren(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(DraftConfig.prefRelayMaxChildren, clamped);
    if (mounted) setState(() => _relayMaxChildren = clamped);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _playerCtrl.dispose();
    _seatCtrl.dispose();
    _roundMinCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    final seatCount = int.parse(_seatCtrl.text.trim());
    final roundMin = int.parse(_roundMinCtrl.text.trim());

    setState(() => _creating = true);

    try {
      await context.read<DraftSessionNotifier>().createAndHost(
        name: _nameCtrl.text.trim().isEmpty
            ? '${_playerCtrl.text.trim()}\'s Draft'
            : _nameCtrl.text.trim(),
        seatCount: seatCount,
        playerName: _playerCtrl.text.trim(),
        roundDurationSeconds: roundMin * 60,
        cubeId: _selectedCubecobraId,
        maxDirectLinks: _maxDirectLinks,
        relayMaxChildren: _relayMaxChildren,
      );

      // Navigation is handled by DraftNavigationController once the notifier
      // reports a hosted session.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _buildDebugCard() {
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, size: 16, color: Colors.red.shade400),
                const SizedBox(width: 8),
                Text(
                  'Debug: topology',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('maxDirectLinks-$_maxDirectLinks'),
              initialValue: _maxDirectLinks,
              decoration: const InputDecoration(
                labelText: 'Max direct connections (host)',
                border: OutlineInputBorder(),
                helperText: 'Set to 1 to force relays with 3 devices',
              ),
              items: [
                for (
                  var i = DraftConfig.minMaxDirectLinks;
                  i <= DraftConfig.maxMaxDirectLinks;
                  i++
                )
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) {
                if (v != null) _setMaxDirectLinks(v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('relayMaxChildren-$_relayMaxChildren'),
              initialValue: _relayMaxChildren,
              decoration: const InputDecoration(
                labelText: 'Relay child limit',
                border: OutlineInputBorder(),
                helperText:
                    'Children this device accepts when acting as a relay',
              ),
              items: [
                for (
                  var i = DraftConfig.minRelayMaxChildren;
                  i <= DraftConfig.maxRelayMaxChildren;
                  i++
                )
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) {
                if (v != null) _setRelayMaxChildren(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Draft')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Draft Name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _playerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter your player name'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _seatCtrl,
                decoration: const InputDecoration(
                  labelText: 'Seats',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final parsed = int.tryParse(v?.trim() ?? '');
                  if (parsed == null) return 'Enter a number';
                  // TODO: Uncomment this again
                  // if (parsed <= 3) return 'Must be greater than 3';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_cubesLoading)
                const LinearProgressIndicator()
              else if (_cubes.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedCubecobraId,
                  decoration: const InputDecoration(
                    labelText: 'Cube (optional)',
                    border: OutlineInputBorder(),
                    helperText: 'Select for CubeCobra draft record submission',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None'),
                    ),
                    ..._cubes.map(
                      (cube) => DropdownMenuItem<String>(
                        value: cube.cubecobraId,
                        child: Text(cube.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => _selectedCubecobraId = v,
                ),
              if (_cubes.isNotEmpty) const SizedBox(height: 16),
              TextFormField(
                controller: _roundMinCtrl,
                decoration: const InputDecoration(
                  labelText: 'Round Duration (minutes)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final parsed = int.tryParse(v?.trim() ?? '');
                  if (parsed == null) return 'Enter a number';
                  if (parsed <= 0) return 'Must be a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              if (_debugEnabled) ...[
                _buildDebugCard(),
                const SizedBox(height: 16),
              ],
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _creating ? null : _create,
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Create Draft',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
