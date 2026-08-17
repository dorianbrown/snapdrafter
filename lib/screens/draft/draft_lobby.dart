import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import 'draft_create.dart';
import 'draft_discovery.dart';
import 'draft_active.dart';
import 'draft_management.dart';
import 'draft_waiting.dart';

class DraftLobbyScreen extends StatefulWidget {
  const DraftLobbyScreen({super.key});

  @override
  State<DraftLobbyScreen> createState() => _DraftLobbyScreenState();
}

class _DraftLobbyScreenState extends State<DraftLobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkExistingSession(),
    );
  }

  void _checkExistingSession() {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final phase = state.session.phase;
    if (phase == DraftPhase.complete || phase == DraftPhase.cancelled) return;

    Widget target;
    if (notifier.isLeader) {
      if (phase == DraftPhase.lobby) {
        target = const DraftManagementScreen();
      } else {
        target = const DraftActiveScreen();
      }
    } else if (notifier.isFollower) {
      if (phase == DraftPhase.lobby) {
        target = const DraftWaitingScreen();
      } else {
        target = const DraftActiveScreen();
      }
    } else {
      return;
    }

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => target));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draft')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.amber.shade900.withValues(alpha: 0.35)
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.amber.shade700 : Colors.amber.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Experimental feature — this draft functionality is '
                          'still a work in progress. Expect bugs and connection '
                          'issues.',
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DraftCreateScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Create Draft',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Host a new draft session and invite players',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DraftDiscoveryScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Scan for Draft',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Find and join a nearby draft session',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
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
