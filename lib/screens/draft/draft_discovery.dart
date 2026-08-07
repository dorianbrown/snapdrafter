import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/draft/draft_ble_follower.dart';
import '../../services/draft/draft_ble_service.dart';
import '../../services/draft/draft_session_notifier.dart';
import 'draft_waiting.dart';

class DraftDiscoveryScreen extends StatefulWidget {
  const DraftDiscoveryScreen({super.key});

  @override
  State<DraftDiscoveryScreen> createState() => _DraftDiscoveryScreenState();
}

class _DraftDiscoveryScreenState extends State<DraftDiscoveryScreen> {
  StreamSubscription<DiscoveredDraft>? _scanSub;
  final List<DiscoveredDraft> _discoveredDrafts = [];
  bool _isScanning = false;
  DraftBleFollower? _scanFollower;
  String _playerName = '';
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _startScan();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _playerName = prefs.getString("username") ?? '';
      });
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanFollower?.stopScan();
    super.dispose();
  }

  void _startScan() {
    _scanFollower = DraftBleFollower();
    _discoveredDrafts.clear();
    setState(() => _isScanning = true);

    _scanSub = _scanFollower!.scanForDrafts().listen(
      (draft) {
        if (mounted) {
          setState(() {
            final idx = _discoveredDrafts.indexWhere(
              (d) => d.deviceId == draft.deviceId,
            );
            if (idx >= 0) {
              _discoveredDrafts[idx] = draft;
            } else {
              _discoveredDrafts.add(draft);
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Scan error: $error')));
          _stopScan();
        }
      },
    );
  }

  void _stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    _scanFollower?.stopScan();
    _scanFollower = null;
    if (mounted) {
      setState(() {
        _isScanning = false;
        _discoveredDrafts.clear();
      });
    }
  }

  Future<void> _joinDraft(DiscoveredDraft draft) async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      await context.read<DraftSessionNotifier>().joinDraft(
        leaderDeviceId: draft.deviceId,
        playerName: _playerName.isEmpty ? 'Player' : _playerName,
      );
      if (mounted) {
        _stopScan();
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DraftWaitingScreen()))
            .then((_) {
              if (mounted) {
                setState(() => _joining = false);
                _startScan();
              }
            });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _joining = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to join: $e')));
      }
    }
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Drafts'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            tooltip: _isScanning ? 'Stop scanning' : 'Start scanning',
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: _joining
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Joining draft...'),
                ],
              ),
            )
          : _isScanning && _discoveredDrafts.isEmpty
          ? const Center(
              child: Text(
                'Scanning for drafts...',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : !_isScanning && _discoveredDrafts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No drafts found',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _startScan,
                    child: const Text('Scan Again'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                _stopScan();
                await Future.delayed(const Duration(milliseconds: 300));
                _startScan();
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _discoveredDrafts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final draft = _discoveredDrafts[index];
                  return ListTile(
                    title: Text(draft.draftName),
                    subtitle: Text(
                      draft.deviceId.length > 24
                          ? '${draft.deviceId.substring(0, 24)}...'
                          : draft.deviceId,
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.signal_cellular_alt,
                          size: 14,
                          color: _rssiColor(draft.rssi),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${draft.rssi} dBm',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _joinDraft(draft),
                  );
                },
              ),
            ),
    );
  }
}
