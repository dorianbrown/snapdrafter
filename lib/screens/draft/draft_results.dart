import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/card.dart' as mtg;
import '../../data/models/deck_upsert.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/deck_repository.dart';
import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import '../../widgets/reconnecting_card.dart';
import '../../widgets/draft/cubecobra_submission_card.dart';
import '../../utils/deck_change_notifier.dart';
import '../deck_scanner.dart';
import 'decklist_preview_sheet.dart';

class DraftResultsScreen extends StatefulWidget {
  const DraftResultsScreen({super.key});

  @override
  State<DraftResultsScreen> createState() => _DraftResultsScreenState();
}

class _DraftResultsScreenState extends State<DraftResultsScreen> {
  final DeckRepository _deckRepository = DeckRepository();
  final CardRepository _cardRepository = CardRepository();
  List<String>? _capturedMainboardIds;
  List<String>? _capturedSideboardIds;
  final Set<String> _savedPlayerIds = {};

  @override
  void initState() {
    super.initState();
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
    final myDeviceId = notifier.myDeviceId;
    final hasSubmitted = notifier.hasSubmittedDecklist(myDeviceId);
    final submittedPlayers =
        state.players.where((p) => p.decklistMainboard != null).toList();
    final unsavedPlayers = submittedPlayers
        .where((p) => !_savedPlayerIds.contains(p.deviceId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${session.name}:  Results'),
        leading: BackButton(
          onPressed: () async {
            await notifier.leaveDraft();
            if (context.mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      ),
      body: standings.isEmpty
          ? const Center(child: Text('No standings available'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (notifier.isReconnecting) const ReconnectingCard(),
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
                if (hasSubmitted)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text('Your decklist has been submitted',
                              style:
                                  Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Final Standings',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ...standings.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final player = entry.value;
                  return _buildStandingRow(rank, player, notifier);
                }),
                const SizedBox(height: 16),
                if (unsavedPlayers.isNotEmpty) ...[
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _saveAllDecklists(unsavedPlayers, session.name),
                      icon: const Icon(Icons.save_alt),
                      label: Text(
                          'Save All Decklists (${unsavedPlayers.length})'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (notifier.isLeader)
                  CubeCobraSubmissionCard(
                    notifier: notifier,
                    cardRepository: _cardRepository,
                  ),
                const SizedBox(height: 16),
              ],
            ),
        floatingActionButton: hasSubmitted || notifier.isReconnecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _scanDeck,
                label: const Text('Scan My Deck'),
                icon: const Icon(Icons.camera_alt),
              ),
      );
  }

  void _scanDeck() async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null || !mounted) return;

    final session = state.session;

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
              session.name,
            );
            _capturedMainboardIds =
                deck.cards.map((c) => c.scryfallId).toList();
            _capturedSideboardIds =
                deck.sideboard.map((c) => c.scryfallId).toList();
            final submitted = await notifier.submitDecklist(
              mainboardScryfallIds: _capturedMainboardIds!,
              sideboardScryfallIds: _capturedSideboardIds ?? [],
            );
            if (!submitted && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Couldn\'t submit decklist — check your connection and try again',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _viewDecklist(DraftPlayer player) async {
    if (player.decklistMainboard == null) return;

    final mainboard = await _cardRepository
        .getCardsByScryfallIds(player.decklistMainboard!);
    final sideboard = player.decklistSideboard != null
        ? await _cardRepository
            .getCardsByScryfallIds(player.decklistSideboard!)
        : <mtg.Card>[];

    if (!mounted) return;

    showDecklistPreviewSheet(
      context,
      playerName: player.playerName,
      mainboard: mainboard,
      sideboard: sideboard,
      onSave: () => _saveDecklistToCollection(player, mainboard, sideboard),
    );
  }

  Future<void> _saveDecklistToCollection(
    DraftPlayer player,
    List<mtg.Card> mainboard,
    List<mtg.Card> sideboard,
  ) async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final upsert = DeckUpsert(
      cards: mainboard,
      sideboard: sideboard,
      name: '${state.session.name} \u2014 ${player.playerName}',
      wins: player.matchWins,
      losses: player.matchLosses,
      draws: player.matchDraws,
      setId: state.session.setCode,
      cubecobraId: state.session.cubeId,
    );

    final savedDeck = await _deckRepository.saveNewDeck(upsert);
    await _deckRepository.addTagToDeck(savedDeck.id, state.session.name);
    setState(() => _savedPlayerIds.add(player.deviceId));
    DeckChangeNotifier().markNeedsRefresh();
  }

  Future<void> _saveAllDecklists(
    List<DraftPlayer> players,
    String draftName,
  ) async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;

    for (final player in players) {
      if (player.decklistMainboard == null) continue;
      final mainboard = await _cardRepository
          .getCardsByScryfallIds(player.decklistMainboard!);
      final sideboard = player.decklistSideboard != null
          ? await _cardRepository
              .getCardsByScryfallIds(player.decklistSideboard!)
          : <mtg.Card>[];

      final upsert = DeckUpsert(
        cards: mainboard,
        sideboard: sideboard,
        name: '$draftName \u2014 ${player.playerName}',
        wins: player.matchWins,
        losses: player.matchLosses,
        draws: player.matchDraws,
        setId: state?.session.setCode,
        cubecobraId: state?.session.cubeId,
      );

      final savedDeck = await _deckRepository.saveNewDeck(upsert);
      await _deckRepository.addTagToDeck(savedDeck.id, state!.session.name);
      _savedPlayerIds.add(player.deviceId);
      DeckChangeNotifier().markNeedsRefresh();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildStandingRow(
      int rank, DraftPlayer player, DraftSessionNotifier notifier) {
    final isMe = player.deviceId == notifier.myDeviceId;
    final hasDecklist = player.decklistMainboard != null;

    Color? rankColor;
    if (rank == 1) rankColor = Colors.amber;
    if (rank == 2) rankColor = Colors.grey.shade400;
    if (rank == 3) rankColor = Colors.brown.shade300;

    return Card(
      color: isMe
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
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
                  fontWeight: rank == 1
                      ? FontWeight.bold
                      : FontWeight.normal,
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
            if (hasDecklist)
              IconButton(
                icon: const Icon(Icons.visibility, size: 18),
                tooltip: 'View decklist',
                onPressed: () => _viewDecklist(player),
                visualDensity: VisualDensity.compact,
              ),
            if (hasDecklist)
              IconButton(
                icon: Icon(
                  _savedPlayerIds.contains(player.deviceId)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  size: 18,
                  color: _savedPlayerIds.contains(player.deviceId)
                      ? Colors.green
                      : null,
                ),
                tooltip: 'Save decklist',
                onPressed: _savedPlayerIds.contains(player.deviceId)
                    ? null
                    : () => _viewDecklist(player),
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 4),
            Icon(
              hasDecklist ? Icons.style : Icons.style_outlined,
              size: 18,
              color: hasDecklist ? Colors.green : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
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
