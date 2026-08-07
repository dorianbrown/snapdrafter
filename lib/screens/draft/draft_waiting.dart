import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import '../../widgets/reconnecting_card.dart';
import 'draft_active.dart';

class DraftWaitingScreen extends StatefulWidget {
  const DraftWaitingScreen({super.key});

  @override
  State<DraftWaitingScreen> createState() => _DraftWaitingScreenState();
}

class _DraftWaitingScreenState extends State<DraftWaitingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchPhase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DraftSessionNotifier>().refreshFromLeader();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<DraftSessionNotifier>().refreshFromLeader();
    }
  }

  void _watchPhase() {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state != null) {
      final phase = state.session.phase;
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
        title: const Text('Leave Draft?'),
        content: const Text(
          'Leaving will drop you from the draft. You can rejoin later if the host hasn\'t started.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Drop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await notifier.dropFromDraft();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DraftSessionNotifier>();
    final state = notifier.state;

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Waiting Room')),
        body: const Center(child: Text('Draft session lost')),
      );
    }

    final session = state.session;

    if (session.phase == DraftPhase.inProgress ||
        session.phase == DraftPhase.seatingsAssigned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToActive();
      });
    }

    if (session.phase == DraftPhase.cancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The host cancelled the draft')),
          );
          await notifier.leaveDraft();
          if (mounted) {
            Navigator.of(context)
                .popUntil((route) => route.isFirst || route.settings.name == 'draft_lobby');
          }
        }
      });
    }

    final myPlayer = state.getPlayer(notifier.myDeviceId);
    if (myPlayer != null && myPlayer.status == PlayerStatus.dropped) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You were removed from the draft')),
          );
          await notifier.leaveDraft();
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      });
    }

    final host = state.getPlayer(state.leaderDeviceId ?? '');

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
          title: const Text('Waiting Room'),
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
                      Row(
                        children: [
                          const Icon(Icons.bluetooth_connected, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Connected to ${session.name}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const Divider(),
                      _infoRow('Host', host?.playerName ?? state.leaderDeviceId ?? 'Unknown'),
                      _infoRow('Seats', '${state.acceptedPlayers.length} / ${session.seatCount}'),
                      _infoRow('Rounds', '${session.totalRounds}'),
                      _infoRow('Round Duration',
                          '${session.roundDurationSeconds ~/ 60} min'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (notifier.isReconnecting) const ReconnectingCard(),
              const SizedBox(height: 8),
              Text('Players (${state.players.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (state.players.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Waiting for players...',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                )
              else
                ...state.players.map((p) => _buildPlayerTile(p, state)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final shouldDrop = await _onWillPop();
            if (shouldDrop && mounted) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.exit_to_app),
          label: const Text('Drop from Draft'),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPlayerTile(DraftPlayer player, DraftState state) {
    final isHost = player.deviceId == state.leaderDeviceId;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isHost ? Colors.deepPurple : (player.status == PlayerStatus.accepted ? Colors.green : Colors.orange),
        radius: 14,
        child: isHost
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
            child: Text(player.playerName, overflow: TextOverflow.ellipsis),
          ),
          if (isHost)
            const Text(' (Host)',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isHost
              ? Colors.deepPurple
              : (player.status == PlayerStatus.accepted ? Colors.green : Colors.orange),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isHost ? 'host' : player.status.name,
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
