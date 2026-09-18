import 'package:flutter/material.dart';

import '../../services/draft/draft_session_notifier.dart';
import '../../services/draft/draft_state.dart';
import 'draft_active.dart';
import 'draft_management.dart';
import 'draft_results.dart';
import 'draft_waiting.dart';

/// Screens owned by the draft session lifecycle.
enum DraftTarget { management, waiting, active, results }

/// Single owner of phase-based draft navigation.
///
/// Screens no longer navigate on state changes; they only mutate the
/// [DraftSessionNotifier] (create, join, leave, drop). This controller listens
/// to the notifier once, computes the screen implied by role + phase, and
/// pushes it at most once per transition. That removes the per-screen
/// listener/guard machinery and the stacked-route class of bug entirely.
class DraftNavigationController {
  DraftNavigationController({required this.navigatorKey, this.messengerKey});

  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  DraftSessionNotifier? _notifier;
  DraftTarget? _lastTarget;
  bool _endingSession = false;

  void attach(DraftSessionNotifier notifier) {
    if (identical(notifier, _notifier)) return;
    _notifier?.removeListener(_onChanged);
    _notifier = notifier;
    notifier.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => sync());
  }

  void detach() {
    _notifier?.removeListener(_onChanged);
    _notifier = null;
  }

  /// Reconciles the navigator with the current draft state. Safe to call
  /// repeatedly; the current target is tracked so no screen is pushed twice.
  void sync() {
    final notifier = _notifier;
    if (notifier == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final state = notifier.state;
    final role = notifier.role;

    // Session ended (or was never started): return to the app root.
    if (role == DraftRole.none || state == null) {
      _endingSession = false;
      if (_lastTarget != null) {
        _lastTarget = null;
        navigator.popUntil((route) => route.isFirst);
      }
      return;
    }

    final phase = state.session.phase;
    final myPlayer = state.getPlayer(notifier.myDeviceId);
    final dropped =
        role == DraftRole.follower &&
        myPlayer != null &&
        myPlayer.status == PlayerStatus.dropped;

    if (!_endingSession && (phase == DraftPhase.cancelled || dropped)) {
      _endingSession = true;
      _lastTarget = null;
      _showMessage(
        phase == DraftPhase.cancelled
            ? 'The host cancelled the draft'
            : 'You were removed from the draft',
      );
      notifier.leaveDraft();
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    if (_endingSession) return;

    final target = switch (phase) {
      DraftPhase.lobby =>
        role == DraftRole.leader ? DraftTarget.management : DraftTarget.waiting,
      DraftPhase.inProgress => DraftTarget.active,
      DraftPhase.complete => DraftTarget.results,
      DraftPhase.cancelled => DraftTarget.management,
    };

    if (target == _lastTarget) return;
    _lastTarget = target;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _screenFor(target)),
      (route) => route.isFirst,
    );
  }

  Widget _screenFor(DraftTarget target) {
    switch (target) {
      case DraftTarget.management:
        return const DraftManagementScreen();
      case DraftTarget.waiting:
        return const DraftWaitingScreen();
      case DraftTarget.active:
        return const DraftActiveScreen();
      case DraftTarget.results:
        return const DraftResultsScreen();
    }
  }

  void _onChanged() => sync();

  void _showMessage(String message) {
    final messenger = messengerKey?.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
