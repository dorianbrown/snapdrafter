import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import 'draft_active.dart';

class DraftManagementScreen extends StatefulWidget {
  const DraftManagementScreen({super.key});

  @override
  State<DraftManagementScreen> createState() => _DraftManagementScreenState();
}

class _DraftManagementScreenState extends State<DraftManagementScreen> {
  @override
  void initState() {
    super.initState();
    _watchPhase();
  }

  void _watchPhase() {
    final notifier = context.read<DraftSessionNotifier>();
    if (notifier.state != null) {
      final phase = notifier.state!.session.phase;
      if (phase == DraftPhase.inProgress || phase == DraftPhase.seatingsAssigned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _navigateToActive();
        });
      }
    }
  }

  void _navigateToActive() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DraftActiveScreen()),
    );
  }

  Future<bool> _onWillPop() async {
    final notifier = context.read<DraftSessionNotifier>();
    if (notifier.state == null) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Draft?'),
        content: const Text(
          'Leaving will cancel the draft for all connected players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Draft', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await notifier.leaveDraft();
      return true;
    }
    return false;
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

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DraftSessionNotifier>();
    final state = notifier.state;

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Draft Lobby')),
        body: const Center(child: Text('Draft session lost')),
      );
    }

    final session = state.session;
    final accepted = state.acceptedPlayers.length;
    final isFull = accepted >= session.seatCount;

    if (session.phase == DraftPhase.inProgress ||
        session.phase == DraftPhase.seatingsAssigned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToActive();
      });
    }
    if (session.phase == DraftPhase.complete || session.phase == DraftPhase.cancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(session.name),
          leading: BackButton(
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Draft Configuration',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Divider(),
                      _infoRow('Name', session.name),
                      _infoRow('Seats', '$accepted / ${session.seatCount}'),
                      _infoRow('Rounds', '${session.totalRounds}'),
                      _infoRow('Round Duration', '${session.roundDurationSeconds ~/ 60} min'),
                      _infoRow('Session ID', session.sessionId, monospace: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Players (${state.players.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (isFull)
                    ElevatedButton.icon(
                      onPressed: () => notifier.closeLobby(),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start Draft'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.players.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Waiting for players to join...',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                )
              else
                ...state.players.map((p) => _buildPlayerTile(p, notifier)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerTile(DraftPlayer player, DraftSessionNotifier notifier) {
    final isLeader = player.deviceId == notifier.state?.leaderDeviceId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isLeader
              ? Colors.deepPurple
              : _statusColor(player.status),
          radius: 14,
          child: isLeader
              ? const Icon(Icons.workspace_premium, color: Colors.white, size: 16)
              : Text(
                  player.playerName.isNotEmpty
                      ? player.playerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                player.playerName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLeader) const Text(' (Host)', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        subtitle: Text(
          player.deviceId.length > 20
              ? '${player.deviceId.substring(0, 20)}...'
              : player.deviceId,
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLeader ? Colors.deepPurple : _statusColor(player.status),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isLeader ? 'host' : player.status.name,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            if (!isLeader)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                tooltip: 'Kick player',
                onPressed: () => notifier.removePlayer(player.deviceId),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: monospace ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
