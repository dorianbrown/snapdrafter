import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://cubecobra.com';
const _userAgent = 'SnapDrafter/1.0';

const kStepResolvingRecord = 'Resolving record…';
const kStepCreatingRecord = 'Creating new record…';
const kStepUploadingDeck = 'Uploading deck…';

class CubeRecordSummary {
  final String id;
  final String name;
  final int date;
  final List<String> playerNames;

  const CubeRecordSummary({
    required this.id,
    required this.name,
    required this.date,
    required this.playerNames,
  });
}

class CubeSubmitResult {
  final String recordId;
  final int decksInRecord;

  const CubeSubmitResult({
    required this.recordId,
    required this.decksInRecord,
  });
}

class CookieExpiredException implements Exception {
  final String message;
  CookieExpiredException(this.message);

  @override
  String toString() => 'CookieExpiredException: $message';
}

enum CubeAuthResult { valid, expired, notOwner }

class CubeCobraApiException implements Exception {
  final String message;
  final int? statusCode;
  CubeCobraApiException(this.message, {this.statusCode});

  @override
  String toString() => 'CubeCobraApiException: $message (status: $statusCode)';
}

class RecordNotFoundException extends CubeCobraApiException {
  RecordNotFoundException(super.message, {super.statusCode});
}

String _extractCookie(String setCookieHeader) {
  final match = RegExp(r'connect\.sid=([^;]+)', caseSensitive: false)
      .firstMatch(setCookieHeader);
  if (match != null) {
    return match.group(1)!;
  }
  throw CubeCobraApiException('No connect.sid cookie found in response');
}

Map<String, String> _formHeaders({String? cookie}) {
  final headers = <String, String>{
    HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
    HttpHeaders.acceptHeader: '*/*',
    HttpHeaders.userAgentHeader: _userAgent,
  };
  if (cookie != null && cookie.isNotEmpty) {
    headers[HttpHeaders.cookieHeader] = 'connect.sid=$cookie';
  }
  return headers;
}

Future<String> login(String username, String password) async {
  final client = http.Client();
  try {
    final request = http.Request('POST', Uri.parse('$_baseUrl/user/login'));
    request.headers.addAll(_formHeaders());
    request.bodyFields = {
      'username': username,
      'password': password,
    };
    request.followRedirects = false;

    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);

    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) {
      throw CubeCobraApiException(
        'Login failed: incorrect username or password',
      );
    }

    final cookie = _extractCookie(setCookie);
    return cookie;
  } finally {
    client.close();
  }
}

Future<CubeAuthResult> validateCubeAuth(String cubeId, String cookie) async {
  try {
    final response = await http.get(
      Uri.parse('$_baseUrl/cube/api/mycubes'),
      headers: _formHeaders(cookie: cookie),
    );

    if (response.statusCode == 403) return CubeAuthResult.expired;

    final location = response.headers['location'] ?? '';
    if (location.contains('/user/login')) return CubeAuthResult.expired;

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final cubes = body['cubes'] as List<dynamic>? ?? [];
      final owns = cubes.any(
        (c) => c['id'] == cubeId || c['shortId'] == cubeId,
      );
      return owns ? CubeAuthResult.valid : CubeAuthResult.notOwner;
    }

    return CubeAuthResult.expired;
  } catch (_) {
    return CubeAuthResult.expired;
  }
}

Future<String> createRecord({
  required String cubeId,
  required String cookie,
  required String recordJson,
}) async {
  final client = http.Client();
  try {
    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/cube/records/create/$cubeId'),
    );
    request.headers.addAll(_formHeaders(cookie: cookie));
    request.bodyFields = {
      'record': recordJson,
      'nickname': 'Your Nickname',
    };
    request.followRedirects = false;

    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);

    final location = response.headers['location'] ?? '';

    if (location.contains('/user/login')) {
      throw CookieExpiredException('Session expired, please sign in again');
    }

    final recordMatch = RegExp(r'/cube/record/([a-f0-9-]+)').firstMatch(location);
    if (recordMatch == null) {
      throw CubeCobraApiException(
        'Failed to create record: could not parse record ID from redirect',
        statusCode: response.statusCode,
      );
    }

    return recordMatch.group(1)!;
  } finally {
    client.close();
  }
}

Future<String> getShareToken(String recordId, String cookie) async {
  final response = await http.get(
    Uri.parse('$_baseUrl/cube/records/sharetoken/$recordId'),
    headers: _formHeaders(cookie: cookie),
  );

  if (response.statusCode == 403) {
    throw RecordNotFoundException(
      'Not authorized to get share token',
      statusCode: 403,
    );
  }

  if (response.statusCode != 200) {
    throw CubeCobraApiException(
      'Failed to get share token',
      statusCode: response.statusCode,
    );
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final token = body['token'] as String?;
  if (token == null) {
    throw CubeCobraApiException('Share token missing from response');
  }

  return token;
}

Future<void> contributeDeck({
  required String recordId,
  required String token,
  required String playerName,
  required List<String> mainboardOracleIds,
  List<String> sideboardOracleIds = const [],
  int wins = 0,
  int losses = 0,
  int draws = 0,
}) async {
  final response = await http.post(
    Uri.parse('$_baseUrl/cube/records/contribute/$recordId'),
    headers: _formHeaders(),
    body: {
      'token': token,
      'mainboard': jsonEncode(mainboardOracleIds),
      'sideboard': jsonEncode(sideboardOracleIds),
      'newPlayer': playerName,
      'wins': wins.toString(),
      'losses': losses.toString(),
      'draws': draws.toString(),
      'nickname': 'Your Nickname',
    },
  );

  if (response.statusCode == 302) {
    final location = response.headers['location'] ?? '';
    if (location.contains('/user/login')) {
      final flash = _extractFlash(response);
      throw CubeCobraApiException(flash ?? 'Contribution rejected');
    }
    if (location.contains('/404')) {
      final flash = _extractFlash(response);
      throw RecordNotFoundException(flash ?? 'Contribution rejected');
    }
    return;
  }

  if (response.statusCode != 200 && response.statusCode != 302) {
    throw CubeCobraApiException(
      'Failed to contribute deck',
      statusCode: response.statusCode,
    );
  }
}

Future<void> addMatchRound(String recordId, String cookie, String roundJson) async {
  final response = await http.post(
    Uri.parse('$_baseUrl/cube/records/edit/round/add/$recordId'),
    headers: _formHeaders(cookie: cookie),
    body: {
      'round': roundJson,
      'nickname': 'Your Nickname',
    },
  );

  if (response.statusCode == 302) {
    final location = response.headers['location'] ?? '';
    if (location.contains('/user/login')) {
      throw CubeCobraApiException('Session expired');
    }
    if (location.contains('/404')) {
      throw CubeCobraApiException('Record not found');
    }
    return;
  }

  if (response.statusCode != 200 && response.statusCode != 302) {
    throw CubeCobraApiException(
      'Failed to add match round',
      statusCode: response.statusCode,
    );
  }
}

Future<List<CubeRecordSummary>> fetchCubeAnalysisData(
  String cubeId,
  String cookie,
) async {
  final response = await http.get(
    Uri.parse('$_baseUrl/cube/records/analysisdata/$cubeId'),
    headers: _formHeaders(cookie: cookie),
  );

  if (response.statusCode == 404) {
    throw CubeCobraApiException(
      'Cube not found or not viewable',
      statusCode: 404,
    );
  }

  if (response.statusCode != 200) {
    throw CubeCobraApiException(
      'Failed to fetch record data from CubeCobra',
      statusCode: response.statusCode,
    );
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final records = body['records'] as List<dynamic>? ?? [];

  return [
    for (final raw in records)
      if (raw is Map<String, dynamic>)
        CubeRecordSummary(
          id: raw['id'] as String? ?? '',
          name: raw['name'] as String? ?? '',
          date: (raw['date'] as num?)?.toInt() ?? 0,
          playerNames: [
            for (final player in (raw['players'] as List<dynamic>? ?? []))
              if (player is Map<String, dynamic> && player['name'] is String)
                player['name'] as String,
          ],
        ),
  ];
}

CubeRecordSummary? findNewestBundleRecord(
  List<CubeRecordSummary> records, {
  String bundleName = 'SnapDrafter decks',
}) {
  CubeRecordSummary? newest;
  for (final record in records) {
    if (record.name != bundleName) continue;
    if (newest == null || record.date > newest.date) newest = record;
  }
  return newest;
}

String makeUniquePlayerName(String name, Set<String> existingNames) {
  if (name.isEmpty) {
    name = 'Deck';
  }
  if (!existingNames.contains(name)) return name;
  var index = 2;
  while (existingNames.contains('$name ($index)')) {
    index++;
  }
  return '$name ($index)';
}

Future<CubeSubmitResult> submitDeckToCube({
  required String cubeId,
  required String cookie,
  required String deckName,
  required List<String> mainboardOracleIds,
  List<String> sideboardOracleIds = const [],
  int wins = 0,
  int losses = 0,
  int draws = 0,
  required void Function(String step) onProgress,
}) async {
  const bundleName = 'SnapDrafter decks';
  const maxPlayers = 16;

  Future<String> createBundleRecord() async {
    onProgress(kStepCreatingRecord);
    final recordJson = jsonEncode({
      'name': bundleName,
      'date': DateTime.now().millisecondsSinceEpoch,
      'description': 'Decks submitted from SnapDrafter',
      'players': [],
      'matches': [],
      'trophy': [],
    });
    return createRecord(cubeId: cubeId, cookie: cookie, recordJson: recordJson);
  }

  Future<CubeSubmitResult> contributeTo(
    String recordId,
    int decksInRecord,
    String playerName,
  ) async {
    onProgress(kStepUploadingDeck);
    final token = await getShareToken(recordId, cookie);
    await contributeDeck(
      recordId: recordId,
      token: token,
      playerName: playerName,
      mainboardOracleIds: mainboardOracleIds,
      sideboardOracleIds: sideboardOracleIds,
      wins: wins,
      losses: losses,
      draws: draws,
    );
    return CubeSubmitResult(
      recordId: recordId,
      decksInRecord: decksInRecord,
    );
  }

  for (var attempt = 0; attempt < 2; attempt++) {
    String recordId;
    int decksInRecord;
    Set<String> existingNames = const {};

    if (attempt == 0) {
      onProgress(kStepResolvingRecord);
      CubeRecordSummary? bundle;
      try {
        final records = await fetchCubeAnalysisData(cubeId, cookie);
        bundle = findNewestBundleRecord(records, bundleName: bundleName);
      } on CubeCobraApiException {
        bundle = null;
      }

      if (bundle != null && bundle.playerNames.length < maxPlayers) {
        recordId = bundle.id;
        decksInRecord = bundle.playerNames.length + 1;
        existingNames = bundle.playerNames.toSet();
      } else {
        recordId = await createBundleRecord();
        decksInRecord = 1;
      }
    } else {
      recordId = await createBundleRecord();
      decksInRecord = 1;
    }

    final playerName = makeUniquePlayerName(deckName, existingNames);
    try {
      return await contributeTo(recordId, decksInRecord, playerName);
    } on RecordNotFoundException {
      if (attempt == 1) rethrow;
    }
  }

  throw StateError('unreachable');
}

String? _extractFlash(http.Response response) {
  final setCookie = response.headers['set-cookie'];
  if (setCookie != null) {
    final flashPattern = RegExp(r'flash=([^;]+)');
    final match = flashPattern.firstMatch(setCookie);
    if (match != null) {
      final raw = match.group(1) ?? '';
      if (raw.startsWith('danger%3A')) {
        return Uri.decodeComponent(raw.substring('danger%3A'.length));
      }
    }
  }
  return null;
}
