import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/deck_upsert.dart';
import '../../data/repositories/deck_repository.dart';
import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import '../deck_scanner.dart';

class DraftResultsScreen extends StatefulWidget {
  const DraftResultsScreen({super.key});

  @override
  State<DraftResultsScreen> createState() => _DraftResultsScreenState();
}

class _DraftResultsScreenState extends State<DraftResultsScreen> {
  final DeckRepository _deckRepository = DeckRepository();
  bool _deckSubmitted = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSubmission();
  }

  Future<void> _checkExistingSubmission() async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final decks = await _deckRepository.getAllDecks();
    final tag = 'draft:${state.session.sessionId}:${notifier.myDeviceId}';
    final submitted = decks.any((d) => d.tags.contains(tag));

    if (mounted) {
      setState(() => _deckSubmitted = submitted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DraftSessionNotifier>();
    final state = notifier.state;

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: Text('Draft session lost')),
      );
    }

    final standings = state.standings;
    final session = state.session;

    return Scaffold(
      appBar: AppBar(title: Text('${session.name} — Results')),
      body: standings.isEmpty
          ? const Center(child: Text('No standings available'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.emoji_events,
                            size: 24, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Text(
                          standings.isNotEmpty
                              ? 'Winner: ${standings.first.playerName}'
                              : 'No winner',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Final Standings',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...standings.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final player = entry.value;
                  return _buildStandingRow(rank, player, notifier);
                }),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _deckSubmitted ? null : _scanDeck,
                    icon: Icon(_deckSubmitted
                        ? Icons.check_circle
                        : Icons.camera_alt),
                    label: Text(_deckSubmitted
                        ? 'Deck Submitted'
                        : 'Scan My Deck'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      await notifier.leaveDraft();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  void _scanDeck() async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final session = state.session;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'scan_deck'),
        builder: (context) => DeckScanner(
          prefill: DeckUpsert(
            cards: const [],
            name: session.name,
            setId: session.setCode,
            cubecobraId: session.cubeId,
          ),
          onDeckSaved: (deck) async {
            await _deckRepository.addTagToDeck(
              deck.id,
              'draft:${session.sessionId}:${notifier.myDeviceId}',
            );
            setState(() => _deckSubmitted = true);
          },
        ),
      ),
    );
  }

  Widget _buildStandingRow(int rank, DraftPlayer player, DraftSessionNotifier notifier) {
    final isMe = player.deviceId == notifier.myDeviceId;

    Color? rankColor;
    if (rank == 1) rankColor = Colors.amber;
    if (rank == 2) rankColor = Colors.grey.shade400;
    if (rank == 3) rankColor = Colors.brown.shade300;

    return Card(
      color: isMe
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor ?? Colors.grey.shade200,
          radius: 16,
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: rank <= 3 ? Colors.black87 : Colors.grey,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                player.playerName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: rank == 1 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isMe)
              const Text(' (you)',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        subtitle: Text(
          'Points: ${player.matchPoints}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _deckSubmitted && isMe
                  ? Icons.style
                  : Icons.style_outlined,
              size: 18,
              color: _deckSubmitted && isMe
                  ? Colors.green
                  : Colors.grey.shade400,
            ),
            const SizedBox(width: 8),
            Text(
              '${player.matchWins}-${player.matchLosses}-${player.matchDraws}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
