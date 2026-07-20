import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://cubecobra.com';
const _userAgent = 'SnapDrafter/1.0';

class CookieExpiredException implements Exception {
  final String message;
  CookieExpiredException(this.message);

  @override
  String toString() => 'CookieExpiredException: $message';
}

class CubeCobraApiException implements Exception {
  final String message;
  final int? statusCode;
  CubeCobraApiException(this.message, {this.statusCode});

  @override
  String toString() => 'CubeCobraApiException: $message (status: $statusCode)';
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

Future<bool> isCookieValid(String cookie) async {
  try {
    final response = await http.get(
      Uri.parse('$_baseUrl/cube/api/mycubes'),
      headers: _formHeaders(cookie: cookie),
    );

    if (response.statusCode == 200) return true;

    if (response.statusCode == 403) return false;

    final location = response.headers['location'] ?? '';
    if (location.contains('/user/login')) return false;

    return response.statusCode < 400;
  } catch (e) {
    return false;
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
    throw CubeCobraApiException('Not authorized to get share token', statusCode: 403);
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
    if (location.contains('/user/login') || location.contains('/404')) {
      final flash = _extractFlash(response);
      throw CubeCobraApiException(flash ?? 'Contribution rejected');
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
