import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/draft/draft_state.dart';
import '../services/draft/draft_session_notifier.dart';
import '../services/draft/draft_ble_follower.dart';
import '../services/draft/draft_ble_leader.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  StreamSubscription<DiscoveredDraft>? _scanSub;
  final List<DiscoveredDraft> _discoveredDrafts = [];
  bool _isScanning = false;
  DraftBleFollower? _scanFollower;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString("username") ?? 'DebugUser';
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanSub = null;
    _scanFollower?.stopScan();
    _scanFollower = null;
    super.dispose();
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  void _startScan() {
    _scanFollower = DraftBleFollower();
    _discoveredDrafts.clear();
    _scanSub = _scanFollower!.scanForDrafts().listen(
      (draft) {
        setState(() {
          final idx =
              _discoveredDrafts.indexWhere((d) => d.deviceId == draft.deviceId);
          if (idx >= 0) {
            _discoveredDrafts[idx] = draft;
          } else {
            _discoveredDrafts.add(draft);
          }
        });
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan error: $error')),
          );
        }
        _stopScan();
      },
    );
    setState(() => _isScanning = true);
  }

  void _stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    _scanFollower?.stopScan();
    _scanFollower = null;
    setState(() {
      _isScanning = false;
      _discoveredDrafts.clear();
    });
  }

  Future<void> _connectToDraft(DiscoveredDraft draft) async {
    final notifier = context.read<DraftSessionNotifier>();
    if (_isScanning) _stopScan();
    try {
      await notifier.joinDraft(
        leaderDeviceId: draft.deviceId,
        playerName: _userName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }

  void _showCreateDraftDialog() {
    final nameCtrl = TextEditingController(text: 'Debug Draft');
    final seatCtrl = TextEditingController(text: '8');
    final playerCtrl = TextEditingController(text: _userName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create Draft Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: 'Draft Name'),
            ),
            TextField(
              controller: seatCtrl,
              decoration: InputDecoration(labelText: 'Seat Count'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: playerCtrl,
              decoration: InputDecoration(labelText: 'Player Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final notifier = context.read<DraftSessionNotifier>();
              try {
                await notifier.createAndHost(
                  name: nameCtrl.text,
                  seatCount: int.parse(seatCtrl.text),
                  playerName: playerCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create draft: $e')),
                  );
                }
              }
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DraftSessionNotifier>();

    return Scaffold(
      appBar: AppBar(title: Text('Debug \u2014 Draft BLE')),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildLeftPane(notifier),
                ),
                VerticalDivider(width: 1),
                Expanded(
                  flex: 3,
                  child: _buildStateView(notifier),
                ),
              ],
            ),
          ),
          _buildBottomButtons(notifier),
        ],
      ),
    );
  }

  Widget _buildLeftPane(DraftSessionNotifier notifier) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(8),
      child: Column(
        children: [
          _buildLeaderSection(notifier),
          SizedBox(height: 8),
          _buildFollowersSection(notifier),
          SizedBox(height: 8),
          _buildAvailableDraftsSection(),
        ],
      ),
    );
  }

  Widget _buildLeaderSection(DraftSessionNotifier notifier) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leader', style: Theme.of(context).textTheme.titleSmall),
            Divider(),
            if (notifier.role == DraftRole.none)
              Text('Not in a draft session',
                  style: TextStyle(color: Colors.grey)),
            if (notifier.isLeader && notifier.state != null) ...[
              _infoRow('Role', 'Leader'),
              _infoRow('Session', notifier.state!.session.name),
              _infoRow('Phase', notifier.state!.session.phase.name),
              _infoRow('Seats', '${notifier.state!.session.seatCount}'),
              _infoRow('Rounds',
                  '${notifier.state!.rounds.length}/${notifier.state!.session.totalRounds}'),
              _infoRow('ID', notifier.state!.session.sessionId,
                  monospace: true),
            ],
            if (notifier.isFollower && notifier.state != null) ...[
              _infoRow('Role', 'Follower'),
              _infoRow('Leader ID', notifier.state!.players
                  .firstWhere((p) => p.deviceId == notifier.state!.leaderDeviceId,
                      orElse: () => DraftPlayer(
                          deviceId: 'unknown',
                          playerName: 'unknown',
                          deviceName: '',
                          joinOrder: 0))
                  .playerName),
              _infoRow('Session', notifier.state!.session.name),
              _infoRow('Phase', notifier.state!.session.phase.name),
              _infoRow('Seats', '${notifier.state!.session.seatCount}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFollowersSection(DraftSessionNotifier notifier) {
    final players = notifier.state?.players ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Followers (${players.where((p) => p.deviceId != notifier.state?.leaderDeviceId).length})',
                style: Theme.of(context).textTheme.titleSmall),
            Divider(),
            if (players.isEmpty)
              Text('No players', style: TextStyle(color: Colors.grey))
            else
              ...players.map((p) => _buildPlayerTile(p, notifier)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerTile(DraftPlayer player, DraftSessionNotifier notifier) {
    final isLeader =
        notifier.state != null && player.deviceId == notifier.state!.leaderDeviceId;
    final isMe = player.deviceId == notifier.myDeviceId;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player.playerName}${isLeader ? " (L)" : ""}${isMe ? " (me)" : ""}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  player.deviceId.length > 16
                      ? '${player.deviceId.substring(0, 16)}...'
                      : player.deviceId,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor(player.status),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              player.status.name,
              style: TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
          if (player.seatNumber != null) ...[
            SizedBox(width: 4),
            Text('S${player.seatNumber}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
          SizedBox(width: 4),
          Text(
            '${player.matchWins}-${player.matchLosses}-${player.matchDraws}',
            style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableDraftsSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isScanning
                        ? 'Available Drafts (scanning...)'
                        : 'Available Drafts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_isScanning)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            Divider(),
            if (!_isScanning && _discoveredDrafts.isEmpty)
              Text('Press "Scan for Drafts" to discover sessions',
                  style: TextStyle(color: Colors.grey))
            else if (_isScanning && _discoveredDrafts.isEmpty)
              Text('Scanning... no drafts found yet',
                  style: TextStyle(color: Colors.grey))
            else
              ..._discoveredDrafts.map((d) => _buildDraftTile(d)),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftTile(DiscoveredDraft draft) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(draft.draftName, style: TextStyle(fontSize: 13)),
      subtitle: Text(
        draft.deviceId.length > 20
            ? '${draft.deviceId.substring(0, 20)}...'
            : draft.deviceId,
        style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_alt,
              size: 14, color: _rssiColor(draft.rssi)),
          SizedBox(width: 2),
          Text('${draft.rssi} dBm',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      onTap: () => _connectToDraft(draft),
    );
  }

  Widget _buildStateView(DraftSessionNotifier notifier) {
    String text;
    if (notifier.state != null) {
      try {
        final encoder = JsonEncoder.withIndent('  ');
        text = encoder.convert(notifier.state!.toJson());
      } catch (e) {
        text = 'Error encoding state: $e';
      }
    } else {
      text = 'No draft state';
    }

    return Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draft State (JSON)',
                style: Theme.of(context).textTheme.titleSmall),
            Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons(DraftSessionNotifier notifier) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    notifier.role != DraftRole.none ? null : _showCreateDraftDialog,
                icon: Icon(Icons.add, size: 18),
                label: Text('Create Draft Session'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _toggleScan,
                icon:
                    Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching, size: 18),
                label: Text(_isScanning ? 'Stop Scan' : 'Scan for Drafts'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool monospace = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('$label:',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: monospace ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.accepted:
        return Colors.green;
      case PlayerStatus.pending:
        return Colors.orange;
      case PlayerStatus.dropped:
        return Colors.red;
    }
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}
