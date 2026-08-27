import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/cubecobra_config.dart';
import '../data/models/deck.dart';
import '../services/cubecobra_api.dart';

const _steps = [
  kStepResolvingRecord,
  kStepCreatingRecord,
  kStepUploadingDeck,
];

enum _SubmitState {
  checking,
  signInRequired,
  notOwner,
  expired,
  ready,
  submitting,
  success,
  failure,
}

Future<void> showCubeCobraSubmitDialog(
  BuildContext context, {
  required Deck deck,
  String? cubeName,
}) {
  return showDialog(
    context: context,
    builder: (_) => _CubeCobraSubmitDialog(deck: deck, cubeName: cubeName),
  );
}

class _CubeCobraSubmitDialog extends StatefulWidget {
  final Deck deck;
  final String? cubeName;

  const _CubeCobraSubmitDialog({required this.deck, this.cubeName});

  @override
  State<_CubeCobraSubmitDialog> createState() => _CubeCobraSubmitDialogState();
}

class _CubeCobraSubmitDialogState extends State<_CubeCobraSubmitDialog> {
  _SubmitState _state = _SubmitState.checking;
  String? _ccUsername;
  String? _cookie;
  String? _signInError;
  String? _errorMessage;
  bool _signingIn = false;
  int _currentStep = -1;
  String? _recordId;
  int _decksInRecord = 0;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String get _deckName => widget.deck.name ?? 'Deck ${widget.deck.ymd}';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    final cubeId = widget.deck.cubecobraId;
    if (cubeId == null) {
      setState(() {
        _state = _SubmitState.failure;
        _errorMessage = 'This deck is not linked to a cube.';
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final credsJson = prefs.getString('cc_auth_$cubeId');
    if (credsJson == null) {
      if (mounted) setState(() => _state = _SubmitState.signInRequired);
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

    if (!mounted) return;
    setState(() {
      _ccUsername = creds.username;
      _cookie = creds.cookie;
      _state = switch (result) {
        CubeAuthResult.valid => _SubmitState.ready,
        CubeAuthResult.notOwner => _SubmitState.notOwner,
        CubeAuthResult.expired => _SubmitState.expired,
      };
    });
  }

  Future<void> _signIn() async {
    final cubeId = widget.deck.cubecobraId!;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _signingIn = true;
      _signInError = null;
    });

    try {
      final cookie = await login(username, password);
      final authResult = await validateCubeAuth(cubeId, cookie);

      if (authResult == CubeAuthResult.notOwner) {
        setState(() {
          _signingIn = false;
          _signInError =
              'You do not own this cube. Only the cube owner can submit decks.';
        });
        return;
      }

      final creds = CubeCobraCredentials(
        cubeId: cubeId,
        username: username,
        cookie: cookie,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cc_auth_$cubeId', jsonEncode(creds.toJson()));

      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _ccUsername = username;
        _cookie = cookie;
        _state = _SubmitState.ready;
      });
    } on CubeCobraApiException catch (e) {
      setState(() {
        _signingIn = false;
        _signInError = e.message;
      });
    } catch (e) {
      setState(() {
        _signingIn = false;
        _signInError = 'Sign in failed: $e';
      });
    }
  }

  Future<void> _reAuth() async {
    final cubeId = widget.deck.cubecobraId!;
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() {
      _signingIn = true;
      _signInError = null;
    });

    try {
      final newCookie = await login(_ccUsername!, password);
      final authResult = await validateCubeAuth(cubeId, newCookie);

      if (authResult == CubeAuthResult.notOwner) {
        if (mounted) setState(() => _state = _SubmitState.notOwner);
        return;
      }

      final creds = CubeCobraCredentials(
        cubeId: cubeId,
        username: _ccUsername!,
        cookie: newCookie,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cc_auth_$cubeId', jsonEncode(creds.toJson()));

      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _cookie = newCookie;
        _state = _SubmitState.ready;
      });
    } on CubeCobraApiException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _signInError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _signInError = 'Sign in failed: $e';
        });
      }
    }
  }

  Future<void> _submit() async {
    final cubeId = widget.deck.cubecobraId;
    if (cubeId == null) {
      setState(() {
        _state = _SubmitState.failure;
        _errorMessage = 'This deck is not linked to a cube.';
      });
      return;
    }

    if (widget.deck.cards.isEmpty) {
      setState(() {
        _state = _SubmitState.failure;
        _errorMessage = 'This deck has no cards to submit.';
      });
      return;
    }

    setState(() {
      _state = _SubmitState.submitting;
      _currentStep = -1;
      _errorMessage = null;
    });

    try {
      final result = await submitDeckToCube(
        cubeId: cubeId,
        cookie: _cookie!,
        deckName: _deckName,
        mainboardOracleIds:
            widget.deck.cards.map((c) => c.oracleId).toList(),
        sideboardOracleIds:
            widget.deck.sideboard.map((c) => c.oracleId).toList(),
        wins: widget.deck.wins ?? 0,
        losses: widget.deck.losses ?? 0,
        draws: widget.deck.draws ?? 0,
        onProgress: (step) {
          if (mounted) {
            setState(() => _currentStep = _steps.indexOf(step));
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _state = _SubmitState.success;
        _recordId = result.recordId;
        _decksInRecord = result.decksInRecord;
        _currentStep = _steps.length - 1;
      });
    } on CookieExpiredException {
      if (mounted) {
        setState(() {
          _state = _SubmitState.expired;
          _signingIn = false;
        });
      }
    } on CubeCobraApiException catch (e) {
      if (mounted) {
        setState(() {
          _state = _SubmitState.failure;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = _SubmitState.failure;
          _errorMessage =
              'Could not reach CubeCobra. Check your internet connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state != _SubmitState.submitting,
      child: AlertDialog(
        title: _buildTitle(),
        scrollable: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 30,
          vertical: 10,
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildTitle() {
    return Row(
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
        const Expanded(child: Text('Submit to CubeCobra')),
      ],
    );
  }

  Widget _buildContent() {
    return switch (_state) {
      _SubmitState.checking => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      _SubmitState.signInRequired => _buildSignInForm(),
      _SubmitState.notOwner => _buildNotOwner(),
      _SubmitState.expired => _buildReAuthForm(),
      _SubmitState.ready => _buildReady(),
      _SubmitState.submitting => _buildProgress(),
      _SubmitState.success => _buildSuccess(),
      _SubmitState.failure => _buildFailure(),
    };
  }

  Widget _buildDeckInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_deckName, style: Theme.of(context).textTheme.titleSmall),
        Text(
          widget.cubeName ?? 'Cube: ${widget.deck.cubecobraId ?? '—'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSignInForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeckInfo(),
        const SizedBox(height: 12),
        const Text('Sign in to enable deck submissions to CubeCobra.'),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username or Email',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          textInputAction: TextInputAction.next,
          enabled: !_signingIn,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          enabled: !_signingIn,
          onSubmitted: (_) => _signIn(),
        ),
        if (_signInError != null) ...[
          const SizedBox(height: 8),
          Text(
            _signInError!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildReAuthForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeckInfo(),
        const SizedBox(height: 12),
        Text(
          'Your CubeCobra session has expired. Re-enter your password for '
          '$_ccUsername to continue.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          obscureText: true,
          enabled: !_signingIn,
          onSubmitted: (_) => _reAuth(),
        ),
        if (_signInError != null) ...[
          const SizedBox(height: 8),
          Text(
            _signInError!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildNotOwner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeckInfo(),
        const SizedBox(height: 12),
        Text(
          'Signed in as $_ccUsername, but this account does not own '
          '${widget.cubeName ?? 'this cube'}. Only the cube owner can submit '
          'decks.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildReady() {
    final winLoss = widget.deck.winLoss;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeckInfo(),
        const SizedBox(height: 8),
        Text('Signed in as $_ccUsername',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Text(
          'This deck will be added to your "SnapDrafter Decks" record for '
          '${widget.cubeName ?? 'this cube'}. A new record is created '
          'automatically when the current one is full (16 decks).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (winLoss != null) ...[
          const SizedBox(height: 8),
          Text('Record: $winLoss', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeckInfo(),
        const SizedBox(height: 12),
        for (var i = 0; i < _steps.length; i++) _buildStepRow(i),
      ],
    );
  }

  Widget _buildStepRow(int index) {
    final isDone = _currentStep > index;
    final isActive = _currentStep == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isDone
                ? Icons.check_circle
                : isActive
                    ? Icons.hourglass_top
                    : Icons.radio_button_unchecked,
            size: 16,
            color: isDone
                ? Colors.green
                : isActive
                    ? Colors.orange
                    : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            _steps[index],
            style: TextStyle(
              color: isActive ? Colors.orange : null,
              fontWeight: isActive ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Deck submitted successfully',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'cube/record/$_recordId · $_decksInRecord '
          'deck${_decksInRecord == 1 ? '' : 's'} in record',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildFailure() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Submission failed',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Unknown error',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case _SubmitState.signInRequired:
      case _SubmitState.expired:
        return [
          TextButton(
            onPressed: _signingIn ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _signingIn
                ? null
                : _state == _SubmitState.expired
                    ? _reAuth
                    : _signIn,
            child: _signingIn
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign In'),
          ),
        ];
      case _SubmitState.notOwner:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () => setState(() {
              _state = _SubmitState.signInRequired;
              _signInError = null;
            }),
            child: const Text('Sign in with Owner Account'),
          ),
        ];
      case _SubmitState.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('Submit Deck'),
          ),
        ];
      case _SubmitState.submitting:
      case _SubmitState.checking:
        return const [];
      case _SubmitState.success:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (_recordId != null)
            ElevatedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://cubecobra.com/cube/record/$_recordId'),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('View on CubeCobra'),
            ),
        ];
      case _SubmitState.failure:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _submit,
            child: const Text('Retry'),
          ),
        ];
    }
  }
}
