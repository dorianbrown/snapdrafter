import 'package:flutter/material.dart';
import '../../services/draft/draft_session_notifier.dart';

/// Shows a dialog for the player to report match results (wins/losses).
///
/// The dialog enforces a best-of-3 limit: the sum of [myWins] and
/// [opponentWins] cannot exceed [maxWins].
void showMatchResultDialog({
  required BuildContext context,
  required DraftSessionNotifier notifier,
  required int roundNumber,
  required String matchId,
  int initialMyWins = 0,
  int initialOpponentWins = 0,
  int maxWins = 3,
}) {
  int myWins = initialMyWins;
  int opponentWins = initialOpponentWins;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => ListenableBuilder(
        listenable: notifier,
        builder: (context, _) => AlertDialog(
          title: const Text('Report Match Result'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Your Wins',
                  style: TextStyle(fontWeight: FontWeight.w500)),
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
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: myWins + opponentWins < maxWins
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
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: myWins + opponentWins < maxWins
                        ? () => setDialogState(() => opponentWins++)
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
              onPressed: notifier.isReconnecting
                  ? null
                  : () {
                      notifier.submitResult(
                        roundNumber: roundNumber,
                        matchId: matchId,
                        myWins: myWins,
                        opponentWins: opponentWins,
                      );
                      Navigator.pop(ctx);
                    },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    ),
  );
}
