import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/draft/draft_session_notifier.dart';
import 'draft_management.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = '${prefs.getString("username") ?? "Player"}\'s Draft';
      _playerCtrl.text = prefs.getString("username") ?? '';
    });
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
          );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DraftManagementScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create draft: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
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
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter your player name' : null,
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
                  if (parsed <= 3) return 'Must be greater than 3';
                  return null;
                },
              ),
              const SizedBox(height: 16),
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
                      : const Text('Create Draft', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
