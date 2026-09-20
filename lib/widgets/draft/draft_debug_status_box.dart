import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/draft/draft_session_notifier.dart';
import '../../services/draft/draft_state.dart';

/// Red debug box showing this device's draft topology state.
///
/// Renders nothing unless `debug_enabled` is set (long-press About in
/// Settings). Drop into any draft screen with `const DraftDebugStatusBox()`.
class DraftDebugStatusBox extends StatefulWidget {
  const DraftDebugStatusBox({super.key});

  @override
  State<DraftDebugStatusBox> createState() => _DraftDebugStatusBoxState();
}

class _DraftDebugStatusBoxState extends State<DraftDebugStatusBox> {
  bool _debugEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadDebug();
  }

  Future<void> _loadDebug() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _debugEnabled = prefs.getBool('debug_enabled') ?? false);
      }
    } catch (_) {
      // Prefs unavailable (e.g. some tests): stay hidden.
    }
  }

  String _describe(DraftSessionNotifier notifier, DraftState state) {
    final String role;
    if (notifier.isLeader) {
      role = 'host';
    } else if (notifier.isRelaying) {
      role = 'relay';
    } else {
      role = 'leaf';
    }

    final parts = <String>['DEBUG $role'];
    if (!notifier.isLeader) {
      parts.add('parent ${notifier.parentDeviceId ?? '-'}');
    }
    parts.add('seq ${state.sequenceNumber}');
    parts.add(state.session.phase.name);
    if (notifier.isLeader) {
      parts.add('links ${notifier.connectedDeviceCount}');
    }
    if (notifier.isRelaying) {
      parts.add('children ${notifier.relayChildCount}');
    }
    if (notifier.isReconnecting) {
      parts.add('RECONNECTING');
    }
    final advertisingError = notifier.advertisingError;
    if (advertisingError != null) {
      parts.add('ADV ERROR: $advertisingError');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_debugEnabled) return const SizedBox.shrink();
    final notifier = context.watch<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _describe(notifier, state),
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Colors.red,
        ),
      ),
    );
  }
}
