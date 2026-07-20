import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/cubecobra_config.dart';
import '../../data/repositories/card_repository.dart';
import '../../services/cubecobra_api.dart';
import '../../services/draft/draft_state.dart';
import '../../services/draft/draft_session_notifier.dart';

enum CubeCobraState {
  none,
  checking,
  notConfigured,
  notOwner,
  authenticated,
  expired,
  submitting,
  complete,
}

class CubeCobraSubmissionCard extends StatefulWidget {
  final DraftSessionNotifier notifier;
  final CardRepository cardRepository;

  const CubeCobraSubmissionCard({
    super.key,
    required this.notifier,
    required this.cardRepository,
  });

  @override
  State<CubeCobraSubmissionCard> createState() =>
      _CubeCobraSubmissionCardState();
}

class _CubeCobraSubmissionCardState extends State<CubeCobraSubmissionCard> {
  CubeCobraState _ccState = CubeCobraState.none;
  Map<String, String> _ccSubmissionStatus = {};
  String? _ccCubecobraId;
  String? _ccUsername;
  String? _ccCookie;
  String? _ccRecordId;

  @override
  void initState() {
    super.initState();
    _initCubeCobraAuth();
  }

  Future<void> _initCubeCobraAuth() async {
    final state = widget.notifier.state;
    if (state == null) return;

    final cubeId = state.session.cubeId;
    if (cubeId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final credsJson = prefs.getString('cc_auth_$cubeId');
    if (credsJson == null) {
      if (mounted) setState(() => _ccState = CubeCobraState.notConfigured);
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
          CubeAuthResult.valid => CubeCobraState.authenticated,
          CubeAuthResult.notOwner => CubeCobraState.notOwner,
          CubeAuthResult.expired => CubeCobraState.expired,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.notifier.state;
    if (state == null) return const SizedBox.shrink();

    final cubeId = state.session.cubeId;
    if (cubeId == null) return const SizedBox.shrink();

    switch (_ccState) {
      case CubeCobraState.none:
      case CubeCobraState.checking:
        return const SizedBox.shrink();
      case CubeCobraState.notConfigured:
        return _buildNotConfiguredCard();
      case CubeCobraState.notOwner:
        return _buildNotOwnerCard();
      case CubeCobraState.authenticated:
        return _buildSubmitCard(state);
      case CubeCobraState.expired:
        return _buildReAuthCard();
      case CubeCobraState.submitting:
        return _buildProgressCard();
      case CubeCobraState.complete:
        return _buildCompleteCard();
    }
  }

  Widget _buildNotConfiguredCard() {
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
                    Theme.of(context).textTheme.bodyMedium?.color ??
                        Colors.black54,
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
    final cubeId = widget.notifier.state?.session.cubeId;
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

                            final authResult =
                                await validateCubeAuth(cubeId, cookie);

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

                            final prefs =
                                await SharedPreferences.getInstance();
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
                                _ccState = CubeCobraState.authenticated;
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
                                SnackBar(
                                    content: Text('Sign in failed: $e')),
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
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

  Widget _buildNotOwnerCard() {
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

  Widget _buildReAuthCard() {
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

                  final authResult =
                      await validateCubeAuth(_ccCubecobraId!, newCookie);

                  if (authResult == CubeAuthResult.notOwner) {
                    if (mounted) {
                      setState(
                          () => _ccState = CubeCobraState.notOwner);
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
                      _ccState = CubeCobraState.authenticated;
                    });
                  }
                } on CookieExpiredException {
                  if (mounted) {
                    setState(() => _ccState = CubeCobraState.expired);
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

  Widget _buildSubmitCard(DraftState state) {
    final players = state.players;
    final allSubmitted = players
        .where((p) => p.status == PlayerStatus.accepted)
        .every((p) =>
            p.decklistMainboard != null &&
            p.decklistMainboard!.isNotEmpty);
    final submittedCount = players
        .where((p) =>
            p.decklistMainboard != null &&
            p.decklistMainboard!.isNotEmpty)
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
                    Theme.of(context).textTheme.bodyMedium?.color ??
                        Colors.black54,
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
                      hasDeck
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
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
                    ? () => _submitToCubeCobra(state.session.name, state)
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

  Widget _buildProgressCard() {
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
              final isPending =
                  status == 'pending' || status == 'submitting';
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

  Widget _buildCompleteCard() {
    final successCount =
        _ccSubmissionStatus.values.where((s) => s == 'success').length;
    final failCount = _ccSubmissionStatus.values
        .where(
            (s) => s != 'success' && s != 'pending' && s != 'submitting')
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
                  failCount > 0
                      ? Icons.warning_amber
                      : Icons.check_circle,
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

  Future<void> _submitToCubeCobra(
      String draftName, DraftState state) async {
    final players = state.players
        .where((p) =>
            p.status == PlayerStatus.accepted &&
            p.decklistMainboard != null &&
            p.decklistMainboard!.isNotEmpty)
        .toList();

    if (players.isEmpty) return;

    setState(() {
      _ccState = CubeCobraState.submitting;
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
          if (match.isBye ||
              match.aWins == null ||
              match.bWins == null) {
            continue;
          }
          final p1Name =
              playerNames[match.playerAId] ?? match.playerAId;
          final p2Name =
              playerNames[match.playerBId] ?? match.playerBId!;
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

        setState(
            () => _ccSubmissionStatus[player.playerName] = 'submitting');

        String? error;
        for (int attempt = 0; attempt < 3; attempt++) {
          if (attempt > 0) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }

          try {
            final cards = await widget.cardRepository
                .getCardsByScryfallIds(player.decklistMainboard!);
            final mainboardOracleIds =
                cards.map((c) => c.oracleId).toList();

            if (mainboardOracleIds.isEmpty) {
              error =
                  'Card data not found (update card database in Settings)';
              break;
            }

            List<String> sideboardOracleIds = [];
            if (player.decklistSideboard != null &&
                player.decklistSideboard!.isNotEmpty) {
              final sideboardCards = await widget.cardRepository
                  .getCardsByScryfallIds(player.decklistSideboard!);
              sideboardOracleIds =
                  sideboardCards.map((c) => c.oracleId).toList();
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
            _ccSubmissionStatus[player.playerName] = error ?? 'success';
          });
        }
      }
    } on CubeCobraApiException catch (e) {
      if (mounted) {
        setState(() => _ccState = CubeCobraState.complete);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _ccState = CubeCobraState.complete);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not reach CubeCobra. Check your internet connection.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _ccState = CubeCobraState.complete);
    }
  }
}
