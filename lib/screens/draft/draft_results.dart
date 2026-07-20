import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/card.dart' as mtg;
import '../../data/models/cubecobra_config.dart';
import '../../data/models/deck_upsert.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/deck_repository.dart';
import '../../services/cubecobra_api.dart';
import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';
import '../../widgets/reconnecting_card.dart';
import '../../utils/deck_change_notifier.dart';
import '../deck_scanner.dart';
import 'decklist_preview_sheet.dart';

class DraftResultsScreen extends StatefulWidget {
  const DraftResultsScreen({super.key});

  @override
  State<DraftResultsScreen> createState() => _DraftResultsScreenState();
}

enum _CcState { none, checking, notConfigured, notOwner, authenticated, expired, submitting, complete }

class _DraftResultsScreenState extends State<DraftResultsScreen> {
  final DeckRepository _deckRepository = DeckRepository();
  final CardRepository _cardRepository = CardRepository();
  List<String>? _capturedMainboardIds;
  List<String>? _capturedSideboardIds;
  bool _deckCaptured = false;
  final Set<String> _savedPlayerIds = {};

  _CcState _ccState = _CcState.none;
  Map<String, String> _ccSubmissionStatus = {};
  String? _ccCubecobraId;
  String? _ccUsername;
  String? _ccCookie;
  String? _ccRecordId;

  @override
  void initState() {
    super.initState();
    _checkExistingSubmission();
    _initCubeCobraAuth();
  }

  Future<void> _checkExistingSubmission() async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final decks = await _deckRepository.getAllDecks();
    final submitted = decks.any(
      (d) =>
          d.tags.contains(state.session.name) && d.name == state.session.name,
    );

    if (mounted && submitted) {
      setState(() => _deckCaptured = true);
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
    final myDeviceId = notifier.myDeviceId;
    final hasSubmitted = notifier.hasSubmittedDecklist(myDeviceId);
    final submittedPlayers =
        state.players.where((p) => p.decklistMainboard != null).toList();
    final unsavedPlayers = submittedPlayers
        .where((p) => !_savedPlayerIds.contains(p.deviceId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${session.name} \u2014 Results'),
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
                if (notifier.isLeader) _buildCubeCobraSection(notifier),
                const SizedBox(height: 16),
              ],
            ),
        floatingActionButton: hasSubmitted
            ? FloatingActionButton.extended(
                onPressed: null,
                label: const Text('Submitted'),
                icon: const Icon(Icons.check),
              )
            : FloatingActionButton.extended(
                onPressed:
                    _deckCaptured ? _shareDecklist : _scanDeck,
                label: Text(_deckCaptured ? 'Share Decklist' : 'Scan My Deck'),
                icon: Icon(_deckCaptured ? Icons.share : Icons.camera_alt),
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
            setState(() => _deckCaptured = true);
          },
        ),
      ),
    );

    if (_capturedMainboardIds != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showShareDialog();
        }
      });
    }
  }

  void _showShareDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decklist Captured'),
        content: const Text(
            'Share this decklist with all players so they can view and save it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _shareDecklist();
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _shareDecklist() {
    final notifier = context.read<DraftSessionNotifier>();
    if (_capturedMainboardIds == null) return;

    notifier.submitDecklist(
      mainboardScryfallIds: _capturedMainboardIds!,
      sideboardScryfallIds: _capturedSideboardIds ?? [],
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

  Future<void> _initCubeCobraAuth() async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null || !notifier.isLeader) return;

    final cubeId = state.session.cubeId;
    if (cubeId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final credsJson = prefs.getString('cc_auth_$cubeId');
    if (credsJson == null) {
      if (mounted) setState(() => _ccState = _CcState.notConfigured);
      return;
    }

    final creds = CubeCobraCredentials.fromJson(
      jsonDecode(credsJson) as Map<String, dynamic>,
    );

    CubeAuthResult result;
    try {
      result = await validateCubeAuth(cubeId, creds.cookie);
    } catch (_) {
      result = CubeAuthResult.expired;
    }

    if (mounted) {
      setState(() {
        _ccCubecobraId = cubeId;
        _ccUsername = creds.username;
        _ccCookie = creds.cookie;
        _ccState = switch (result) {
          CubeAuthResult.valid => _CcState.authenticated,
          CubeAuthResult.notOwner => _CcState.notOwner,
          CubeAuthResult.expired => _CcState.expired,
        };
      });
    }
  }

  Widget _buildCubeCobraSection(DraftSessionNotifier notifier) {
    final state = notifier.state;
    if (state == null) return const SizedBox.shrink();

    final cubeId = state.session.cubeId;
    if (cubeId == null) return const SizedBox.shrink();

    switch (_ccState) {
      case _CcState.none:
      case _CcState.checking:
        return const SizedBox.shrink();
      case _CcState.notConfigured:
        return _buildCubeCobraNotConfiguredCard();
      case _CcState.notOwner:
        return _buildCubeCobraNotOwnerCard();
      case _CcState.authenticated:
        return _buildCubeCobraSubmitCard(notifier);
      case _CcState.expired:
        return _buildCubeCobraReAuthCard();
      case _CcState.submitting:
        return _buildCubeCobraProgressCard();
      case _CcState.complete:
        return _buildCubeCobraCompleteCard();
    }
  }

  Widget _buildCubeCobraNotConfiguredCard() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/app_icons/monochrome_cubecobra.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Submit to CubeCobra',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to CubeCobra in Settings to submit draft records.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _showInlineSignInDialog,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign In to CubeCobra'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInlineSignInDialog() {
    final notifier = context.read<DraftSessionNotifier>();
    final cubeId = notifier.state?.session.cubeId;
    if (cubeId == null) return;

    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        bool signingIn = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('CubeCobra Sign In'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sign in to enable draft record submissions.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: signingIn
                      ? null
                      : () async {
                          final username = usernameCtrl.text.trim();
                          final password = passwordCtrl.text;
                          if (username.isEmpty || password.isEmpty) return;

                          setDialogState(() => signingIn = true);

                          try {
                            final cookie = await login(username, password);

                            final authResult = await validateCubeAuth(cubeId, cookie);

                            if (authResult == CubeAuthResult.notOwner) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'You do not own this cube. Only the cube owner can submit draft records.',
                                    ),
                                  ),
                                );
                              }
                              setDialogState(() => signingIn = false);
                              return;
                            }

                            final creds = CubeCobraCredentials(
                              cubeId: cubeId,
                              username: username,
                              cookie: cookie,
                            );

                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'cc_auth_$cubeId',
                              jsonEncode(creds.toJson()),
                            );

                            if (ctx.mounted) Navigator.of(ctx).pop();

                            if (mounted) {
                              setState(() {
                                _ccCubecobraId = cubeId;
                                _ccUsername = username;
                                _ccCookie = cookie;
                                _ccState = _CcState.authenticated;
                              });
                            }
                          } on CubeCobraApiException catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Sign in failed: $e')),
                              );
                            }
                          } finally {
                            if (ctx.mounted) {
                              setDialogState(() => signingIn = false);
                            }
                          }
                        },
                  child: signingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCubeCobraNotOwnerCard() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Not a Cube Owner',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You are signed in as $_ccUsername, but do not own this cube. Only the cube owner can submit draft records.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _showInlineSignInDialog,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign in with Owner Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCubeCobraReAuthCard() {
    final passwordCtrl = TextEditingController();

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_problem, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CubeCobra Session Expired',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Re-enter your password for $_ccUsername to continue.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final password = passwordCtrl.text;
                if (password.isEmpty) return;

                try {
                  final newCookie = await login(_ccUsername!, password);

                  final authResult = await validateCubeAuth(_ccCubecobraId!, newCookie);

                  if (authResult == CubeAuthResult.notOwner) {
                    if (mounted) {
                      setState(() => _ccState = _CcState.notOwner);
                    }
                    return;
                  }

                  final creds = CubeCobraCredentials(
                    cubeId: _ccCubecobraId!,
                    username: _ccUsername!,
                    cookie: newCookie,
                  );

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'cc_auth_$_ccCubecobraId',
                    jsonEncode(creds.toJson()),
                  );

                  if (mounted) {
                    setState(() {
                      _ccCookie = newCookie;
                      _ccState = _CcState.authenticated;
                    });
                  }
    } on CookieExpiredException {
      if (mounted) {
        setState(() => _ccState = _CcState.expired);
      }
      return;
    } on CubeCobraApiException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign in failed: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCubeCobraSubmitCard(DraftSessionNotifier notifier) {
    final state = notifier.state!;
    final players = state.players;
    final allSubmitted = players
        .where((p) => p.status == PlayerStatus.accepted)
        .every((p) => p.decklistMainboard != null && p.decklistMainboard!.isNotEmpty);
    final submittedCount = players
        .where((p) => p.decklistMainboard != null && p.decklistMainboard!.isNotEmpty)
        .length;
    final eligibleCount = players
        .where((p) => p.status == PlayerStatus.accepted)
        .length;
    final canSubmit = submittedCount > 0;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/app_icons/monochrome_cubecobra.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black54,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Submit to CubeCobra',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Signed in as $_ccUsername',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...players
                .where((p) => p.status == PlayerStatus.accepted)
                .map((p) {
              final hasDeck = p.decklistMainboard != null &&
                  p.decklistMainboard!.isNotEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      hasDeck ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: hasDeck ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.playerName,
                      style: TextStyle(
                        color: hasDeck ? null : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: canSubmit
                    ? () => _submitToCubeCobra(state.session.name)
                    : null,
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: Text(
                  canSubmit
                      ? allSubmitted
                          ? 'Submit All to CubeCobra ($eligibleCount decks)'
                          : 'Submit $submittedCount of $eligibleCount decks'
                      : 'No decklists available',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCubeCobraProgressCard() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Submitting to CubeCobra...',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._ccSubmissionStatus.entries.map((e) {
              final status = e.value;
              final isSuccess = status == 'success';
              final isPending = status == 'pending' || status == 'submitting';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isPending
                          ? Icons.hourglass_top
                          : isSuccess
                              ? Icons.check_circle
                              : Icons.error,
                      size: 16,
                      color: isPending
                          ? Colors.orange
                          : isSuccess
                              ? Colors.green
                              : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: isPending ? Colors.orange : null,
                        ),
                      ),
                    ),
                    if (!isPending && !isSuccess)
                      Flexible(
                        child: Text(
                          status,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCubeCobraCompleteCard() {
    final successCount =
        _ccSubmissionStatus.values.where((s) => s == 'success').length;
    final failCount = _ccSubmissionStatus.values
        .where((s) => s != 'success' && s != 'pending' && s != 'submitting')
        .length;
    final total = _ccSubmissionStatus.length;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  failCount > 0 ? Icons.warning_amber : Icons.check_circle,
                  color: failCount > 0 ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failCount > 0
                        ? 'Submitted $successCount/$total decks'
                        : 'All $successCount decks submitted',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (_ccRecordId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Record: cube/record/$_ccRecordId',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitToCubeCobra(String draftName) async {
    final notifier = context.read<DraftSessionNotifier>();
    final state = notifier.state;
    if (state == null) return;

    final players = state.players
        .where((p) =>
            p.status == PlayerStatus.accepted &&
            p.decklistMainboard != null &&
            p.decklistMainboard!.isNotEmpty)
        .toList();

    if (players.isEmpty) return;

    setState(() {
      _ccState = _CcState.submitting;
      _ccSubmissionStatus = {
        for (final p in players) p.playerName: 'pending',
      };
    });

    try {
      final recordJson = jsonEncode({
        'name': draftName,
        'date': DateTime.now().millisecondsSinceEpoch,
        'players': [],
        'description': 'Drafted with SnapDrafter',
        'matches': [],
        'trophy': [],
      });

      final recordId = await createRecord(
        cubeId: _ccCubecobraId!,
        cookie: _ccCookie!,
        recordJson: recordJson,
      );

      _ccRecordId = recordId;

      final token = await getShareToken(recordId, _ccCookie!);

      final playerNames = {
        for (final p in state.players) p.deviceId: p.playerName,
      };

      for (final round in state.rounds) {
        final roundMatches = <Map<String, dynamic>>[];
        for (final match in round.matches) {
          if (match.isBye || match.aWins == null || match.bWins == null) continue;
          final p1Name = playerNames[match.playerAId] ?? match.playerAId;
          final p2Name = playerNames[match.playerBId] ?? match.playerBId!;
          roundMatches.add({
            'p1': p1Name,
            'p2': p2Name,
            'results': [match.aWins, match.bWins, 0],
          });
        }
        if (roundMatches.isNotEmpty) {
          try {
            await addMatchRound(
              recordId,
              _ccCookie!,
              jsonEncode({'matches': roundMatches}),
            );
          } catch (_) {}
        }
      }

      for (final player in players) {
        if (!mounted) return;

        setState(() => _ccSubmissionStatus[player.playerName] = 'submitting');

        String? error;
        for (int attempt = 0; attempt < 3; attempt++) {
          if (attempt > 0) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }

          try {
            final cards =
                await _cardRepository.getCardsByScryfallIds(player.decklistMainboard!);
            final mainboardOracleIds = cards.map((c) => c.oracleId).toList();

            if (mainboardOracleIds.isEmpty) {
              error = 'Card data not found (update card database in Settings)';
              break;
            }

            List<String> sideboardOracleIds = [];
            if (player.decklistSideboard != null &&
                player.decklistSideboard!.isNotEmpty) {
              final sideboardCards =
                  await _cardRepository.getCardsByScryfallIds(player.decklistSideboard!);
              sideboardOracleIds = sideboardCards.map((c) => c.oracleId).toList();
            }

            await contributeDeck(
              recordId: recordId,
              token: token,
              playerName: player.playerName,
              mainboardOracleIds: mainboardOracleIds,
              sideboardOracleIds: sideboardOracleIds,
              wins: player.matchWins,
              losses: player.matchLosses,
              draws: player.matchDraws,
            );

            error = null;
            break;
          } on CubeCobraApiException catch (e) {
            error = e.message;
          } catch (e) {
            error = '$e';
          }
        }

        if (mounted) {
          setState(() {
            _ccSubmissionStatus[player.playerName] =
                error ?? 'success';
          });
        }
      }
    } on CubeCobraApiException catch (e) {
      if (mounted) {
        setState(() => _ccState = _CcState.complete);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _ccState = _CcState.complete);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reach CubeCobra. Check your internet connection.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _ccState = _CcState.complete);
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
