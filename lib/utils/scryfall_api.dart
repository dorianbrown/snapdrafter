import 'dart:io';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://api.scryfall.com';
const _headers = {
  HttpHeaders.acceptHeader: 'application/json;q=0.9,*/*;q=0.8',
  HttpHeaders.userAgentHeader:
      'SnapDrafter (https://play.google.com/store/apps/details?id=com.dbrown.mtg_draft_tracker&hl=en)',
};

Future<http.Response> scryfallGet(String path) =>
    http.get(Uri.parse('$_baseUrl$path'), headers: _headers);
