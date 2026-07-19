import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import 'draft_results.dart';

class DraftActiveScreen extends StatefulWidget {
  const DraftActiveScreen({super.key});

  @override
  State<DraftActiveScreen> createState() => _DraftActiveScreenState();
}

class _DraftActiveScreenState extends State<DraftActiveScreen> {
  Timer? _tickTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _syncTickTimer();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        context.read<DraftSessionNotifier>().pollState();
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }

  void _syncTickTimer() {
    final notifier = context.read<DraftSessionNotifier>();
    final inProgress = notifier.state != null &&
        notifier.state!.session.phase == DraftPhase.inProgress;

    if (inProgress && _tickTimer == null) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!inProgress && _tickTimer != null) {
      _tickTimer!.cancel();
      _tickTimer = null;
    }
  }

  Future<bool> _onWillPop() async {
    final notifier = context.read<DraftSessionNotifier>();
    if (notifier.state == null) return true;

    final isLeader = notifier.isLeader;
    final title = isLeader ? 'Cancel Draft?' : 'Drop from Draft?';
    final body = isLeader
        ? 'Leaving will cancel the draft for all players.'
        : 'Dropping will remove you from the draft.';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isLeader ? 'Cancel Draft' : 'Drop',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      if (isLeader) {
        await notifier.leaveDraft();
      } else {
        await notifier.dropFromDraft();
      }
      return true;
    }
    return false;
  }

  int _remainingSeconds(DraftRound? round, DraftSession session) {
    if (round == null || round.roundStartTime == null) return 0;
    final endTime =
        round.roundStartTime!.add(Duration(seconds: session.roundDurationSeconds));
    final remaining = endTime.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  void _navigateIfNeeded(DraftSessionNotifier notifier) {
    if (notifier.state == null) return;
    final phase = notifier.state!.session.phase;
    if (phase == DraftPhase.complete) {
      _tickTimer?.cancel();
      _tickTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DraftResultsScreen()),
          );
        }
      });
    } else if (phase == DraftPhase.cancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          notifier.leaveDraft();
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }

    if (notifier.isFollower) {
      final myPlayer = notifier.state!.getPlayer(notifier.myDeviceId);
      if (myPlayer != null && myPlayer.status == PlayerStatus.dropped) {
        _tickTimer?.cancel();
        _tickTimer = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You were removed from the draft')),
            );
            notifier.leaveDraft();
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
      }
    }
  }

  Color _matchStatusColor(MatchStatus status) {
    switch (status) {
      case MatchStatus.pending:
        return Colors.grey;
      case MatchStatus.reported:
        return Colors.orange;
      case MatchStatus.confirmed:
        return Colors.green;
      case MatchStatus.conflicted:
        return Colors.red;
    }
  }

  String _matchStatusLabel(MatchStatus status) {
    switch (status) {
      case MatchStatus.pending:
        return 'Pending';
      case MatchStatus.reported:
        return 'Reported';
      case MatchStatus.confirmed:
        return 'Confirmed';
      case MatchStatus.conflicted:
        return 'Conflict!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DraftSessionNotifier>();
    _syncTickTimer();
    _navigateIfNeeded(notifier);

    final state = notifier.state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Draft')),
        body: const Center(child: Text('Draft session lost')),
      );
    }

    final currentRound =
        state.rounds.isNotEmpty ? state.rounds.last : null;
    final roundNum = currentRound?.roundNumber ?? 0;
    final totalRounds = state.session.totalRounds;
    final remaining = _remainingSeconds(currentRound, state.session);

    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final isExpired = remaining <= 0;

    final myMatch = currentRound != null
        ? state.getMyMatch(notifier.myDeviceId, currentRound.roundNumber)
        : null;

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
          title: Text(state.session.name),
          leading: BackButton(
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (notifier.isReconnecting)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildRoundHeader(roundNum, totalRounds, minutes, seconds, isExpired),
            const Divider(height: 1),
            Expanded(
              child: notifier.isLeader
                  ? _buildLeaderView(state, notifier, currentRound)
                  : _buildFollowerView(state, notifier, myMatch),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundHeader(int roundNum, int totalRounds, String minutes,
      String seconds, bool isExpired) {
    return Container(
      color: isExpired ? Colors.red.shade800 : Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text('Round $roundNum / $totalRounds',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isExpired ? Colors.white : null,
              )),
          const Spacer(),
          Text(
            '$minutes:$seconds',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: isExpired ? Colors.white : null,
            ),
          ),
          if (isExpired) ...[
            const SizedBox(width: 8),
            Text('Time\'s up',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withAlpha(200))),
          ],
        ],
      ),
    );
  }

  Widget _buildLeaderView(
      DraftState state, DraftSessionNotifier notifier, DraftRound? currentRound) {
    if (currentRound == null) {
      return const Center(child: Text('No round data'));
    }

    final myMatch = state.getMyMatch(notifier.myDeviceId, currentRound.roundNumber);
    final hasMyMatch = myMatch != null && !myMatch.isBye;
    final otherMatches = myMatch != null
        ? currentRound.matches.where((m) => m.matchId != myMatch.matchId).toList()
        : currentRound.matches.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMyMatch) ...[
            _buildMyMatchSection(state, notifier, myMatch, currentRound.roundNumber),
            const SizedBox(height: 16),
          ],
          ...otherMatches.map((m) => _buildMatchTile(state, m)),
          const SizedBox(height: 24),
          if (currentRound.complete)
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => notifier.advanceRound(),
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  state.rounds.length >= state.session.totalRounds
                      ? 'Finish Draft'
                      : 'Advance to Round ${state.rounds.length + 1}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            )
          else
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock),
                label: Text(
                    'Waiting for results (${currentRound.matches.where((m) => m.status != MatchStatus.confirmed && !m.isBye).length} remaining)'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchTile(DraftState state, DraftMatch match) {
    final playerA = state.getPlayer(match.playerAId);
    final playerB = match.playerBId != null ? state.getPlayer(match.playerBId!) : null;
    final statusColor = _matchStatusColor(match.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (match.isBye)
              Row(
                children: [
                  const Icon(Icons.person, size: 18),
                  const SizedBox(width: 8),
                  Text('${playerA?.playerName ?? match.playerAId} — Bye',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (playerA != null && playerA.deviceId == state.leaderDeviceId) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.workspace_premium, size: 14, color: Colors.deepPurple),
                  ],
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                              playerA?.playerName ?? match.playerAId,
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        if (playerA != null && playerA.deviceId == state.leaderDeviceId) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.workspace_premium, size: 14, color: Colors.deepPurple),
                        ],
                      ],
                    ),
                  ),
                  if (match.aWins != null)
                    Text('${match.aWins}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                              playerB?.playerName ?? match.playerBId ?? '?',
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        if (playerB != null && playerB.deviceId == state.leaderDeviceId) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.workspace_premium, size: 14, color: Colors.deepPurple),
                        ],
                      ],
                    ),
                  ),
                  if (match.bWins != null)
                    Text('${match.bWins}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              if (match.draws != null && match.draws! > 0) ...[
                const SizedBox(height: 4),
                Text('Draws: ${match.draws}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _matchStatusLabel(match.status),
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowerView(
      DraftState state, DraftSessionNotifier notifier, DraftMatch? myMatch) {
    if (myMatch == null) {
      return const Center(child: Text('No match found for you this round'));
    }

    if (myMatch.isBye) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, size: 48, color: Colors.amber),
            const SizedBox(height: 16),
            const Text('You have a bye this round!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('You automatically get a win.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final roundNumber = state.rounds.last.roundNumber;
    return _buildMyMatchSection(state, notifier, myMatch, roundNumber);
  }

  Widget _buildMyMatchSection(
      DraftState state, DraftSessionNotifier notifier,
      DraftMatch myMatch, int roundNumber) {
    final opponentId = myMatch.playerAId == notifier.myDeviceId
        ? myMatch.playerBId
        : myMatch.playerAId;
    final opponent = opponentId != null ? state.getPlayer(opponentId) : null;

    final canReport = notifier.canReportResult(roundNumber);
    final hasReported = notifier.hasReportedResult(roundNumber);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Your Opponent',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    opponent?.playerName ?? opponentId ?? 'Unknown',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  if (opponent != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        'Record: ${opponent.matchWins}-${opponent.matchLosses}-${opponent.matchDraws}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (hasReported)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Match result submitted'),
                  ],
                ),
              ),
            )
          else if (canReport)
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _showReportResultDialog(
                    notifier, roundNumber, myMatch),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Report Match Result'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Waiting for opponent to confirm'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Match Status',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Divider(),
                  _infoRow('Your score',
                      myMatch.aWins != null ? '${myMatch.aWins} wins' : '—'),
                  _infoRow('Opponent score',
                      myMatch.bWins != null ? '${myMatch.bWins} wins' : '—'),
                  _infoRow('Status', _matchStatusLabel(myMatch.status)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportResultDialog(
      DraftSessionNotifier notifier, int roundNumber, DraftMatch match) {
    int myWins = 0;
    int opponentWins = 0;
    int draws = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report Match Result'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Your Wins', style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: myWins > 0
                        ? () => setDialogState(() => myWins--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$myWins',
                      style:
                          const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: myWins < 3
                        ? () => setDialogState(() => myWins++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Opponent Wins',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: opponentWins > 0
                        ? () => setDialogState(() => opponentWins--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$opponentWins',
                      style:
                          const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: opponentWins < 3
                        ? () => setDialogState(() => opponentWins++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Draws', style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: draws > 0
                        ? () => setDialogState(() => draws--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$draws',
                      style:
                          const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: draws < 3
                        ? () => setDialogState(() => draws++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                notifier.submitResult(
                  roundNumber: roundNumber,
                  matchId: match.matchId,
                  myWins: myWins,
                  opponentWins: opponentWins,
                  draws: draws,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Submit'),
            ),
          ],
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
