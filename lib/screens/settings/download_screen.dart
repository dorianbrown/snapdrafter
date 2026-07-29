import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:http/http.dart' as http;

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/utils/release_date_helper.dart';
import '/data/models/card.dart';
import '/data/models/token.dart';
import '/data/repositories/card_repository.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/token_repository.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  ValueNotifier<String> downloadPhaseNotifier = ValueNotifier("");
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();
  bool isDownloading = false;
  late CardRepository cardRepository;
  late SetRepository setRepository;
  late TokenRepository tokenRepository;
  late ReleaseDateHelper _releaseDateHelper;
  Map<String, dynamic>? scryfallMetadata;

  @override
  initState() {
    super.initState();
    cardRepository = CardRepository();
    setRepository = SetRepository();
    tokenRepository = TokenRepository();
    _releaseDateHelper = ReleaseDateHelper();

    setRepository.populateSetsTable();
    setRepository.getScryfallMetadata().then((value) {
      scryfallMetadata = value;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final metadataStyle = TextStyle(
        fontStyle: FontStyle.italic, color: Theme.of(context).hintColor);
    return Scaffold(
        appBar: AppBar(title: const Text('Scryfall Download')),
        body: Center(
          child: ValueListenableBuilder(
              valueListenable: downloadPhaseNotifier,
              builder: (context, value, snapshot) {
                return Column(
                  spacing: 25,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("Scryfall Card Data",
                        style: TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.w600,
                        )),
                    if (scryfallMetadata != null)
                      Table(
                        columnWidths: {
                          0: FixedColumnWidth(120),
                          1: IntrinsicColumnWidth()
                        },
                        children: [
                          TableRow(children: [
                            Text("Last download:", style: metadataStyle),
                            Text(scryfallMetadata?['datetime'] ?? 'None',
                                style: metadataStyle)
                          ]),
                          TableRow(children: [
                            Text("Latest set:", style: metadataStyle),
                            Text(scryfallMetadata?['newest_set_name'] ?? 'None',
                                style: metadataStyle)
                          ]),
                        ],
                      ),
                    Padding(
                        padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                        child:
                            const Icon(Icons.file_download_outlined, size: 70)),
                    if (isDownloading)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(50, 0, 50, 0),
                        child: CircularProgressIndicator(),
                      ),
                    (isDownloading)
                        ? Text(value,
                            style: const TextStyle(
                                fontSize: 20.0, fontWeight: FontWeight.w600),
                          )
                        : ElevatedButton(
                            onPressed: () {
                              isDownloading = true;
                              downloadFileFromServer();
                              setState(() {});
                            },
                            child: Text("Download Scryfall Data"))
                  ],
                );
              }),
        ));
  }

  downloadFileFromServer() async {
    downloadPhaseNotifier.value = "Querying Scryfall...";

    final getResponse = await http.get(
      Uri.parse("https://api.scryfall.com/bulk-data"),
      headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'}
    );
    String downloadUri;
    if (getResponse.statusCode == 200) {
      var responseMap = jsonDecode(getResponse.body);
      try {
        final dataMap = responseMap["data"]
            .where((x) => x["type"] == "oracle_cards")
            .toList()[0];
        downloadUri = dataMap["jsonl_download_uri"];
      } on Exception catch (e) {
        throw Exception('Unable to connect to api.scryfall.com: $e');
      }
    } else {
      throw Exception(
          'Unable to connect to api.scryfall.com. Status code: ${getResponse.statusCode}');
    }

    downloadPhaseNotifier.value = "Downloading Scryfall data...";
    final downloadResponse = await Dio()
        .get(downloadUri, options: Options(responseType: ResponseType.stream));

    List<String> validCardLayouts = [
      "normal",
      "class",
      "saga",
      "meld",
      "prototype",
      "transform",
      "modal_dfc",
      "split",
      "adventure",
      "augment",
      "flip",
      "mutate",
      "case",
      "leveler",
      "prepare"
    ];
    List<String> validTypes = [
      "Creature",
      "Artifact",
      "Enchantment",
      "Land",
      "Instant",
      "Sorcery",
      "Planeswalker",
      "Battle"
    ];

    mapToCard(Map val) {
      String cardType = "";
      String colors = "";
      String manaCost = "";
      String imageUri = "";
      String? producedMana;
      for (String type in validTypes) {
        if (val["type_line"].contains(type)) {
          cardType = type;
          break;
        }
      }

      if (val["image_uris"] == null && val["card_faces"] != null) {
        imageUri = val["card_faces"][0]["image_uris"]["normal"];
        colors = val["card_faces"][0]["colors"].join("");
        manaCost = val["card_faces"][0]["mana_cost"];
        producedMana = val["card_faces"][0]["produced_mana"] ??
            val["card_faces"][1]["produced_mana"];
      } else {
        imageUri = val["image_uris"]["normal"];
        colors = val["colors"].join("");
        manaCost = val["mana_cost"];
        producedMana = val["produced_mana"]?.join("");
      }

      return Card(
          scryfallId: val["id"],
          oracleId: val["oracle_id"],
          name: val["name"],
          title: val["name"].split(" // ")[0],
          type: cardType,
          colors: colors,
          imageUri: imageUri,
          manaCost: manaCost,
          manaValue: val["cmc"].toInt(),
          producedMana: producedMana);
    }

    List<Card> cards = [];
    List<Token> tokens = [];
    List<List<String>> cardTokenMapping = [];
    Map<String, String> nameOracleMapping = {};
    String newestRelease = "1900-01-01";
    Map<String, dynamic> scryfallMetadata = {
      "id": 1,
      "datetime": convertDatetimeToYMDHM(DateTime.now())
    };
    downloadPhaseNotifier.value = "Unpacking archive...";
    final completer = Completer();
    downloadResponse.data.stream
        .cast<List<int>>()
        .transform(gzip.decoder)
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      final val = jsonDecode(line);
      if (val is! Map) return;
      // Playable Card
      if (validCardLayouts.contains(val["layout"])) {
        if (val["card_faces"] == null && val["image_uris"] == null) return;
        if (newestRelease.compareTo(val["released_at"]) < 0 &&
            val["released_at"].compareTo(convertDatetimeToYMD(
                    DateTime.now().add(Duration(days: 8)))) <
                0 &&
            val["set_type"] == "expansion") {
          newestRelease = val["released_at"];
          scryfallMetadata["newest_set_name"] = val["set_name"];
        }
        nameOracleMapping[val["name"]] = val["oracle_id"];
        cards.add(mapToCard(val));
      }
      // Tokens
      if (val["layout"] == "token") {
        if (val["all_parts"] == null || val["all_parts"].isEmpty) return;
        List<Map<String, dynamic>> allParts = val["all_parts"]
            .whereType<Map<String, dynamic>>()
            .where((obj) => obj["component"] == "combo_piece")
            .toList();
        cardTokenMapping.addAll(allParts
            .map((obj) => [obj["name"] as String, val["oracle_id"] as String]));
        tokens.add(Token(
          oracleId: val["oracle_id"],
          name: val["name"],
          imageUri: val["card_faces"] != null
              ? val["card_faces"][0]["image_uris"]["normal"]
              : val["image_uris"]["normal"],
        ));
      }
    }, onDone: () {
      completer.complete();
    });
    await completer.future;

    downloadPhaseNotifier.value = "Filling database...";
    debugPrint("tokenMapping: ${cardTokenMapping.length}");

    cardTokenMapping = cardTokenMapping
        .where((obj) => nameOracleMapping.keys
            .contains(obj[0])) // Removes non-cards from mapping
        .map((obj) => [
              nameOracleMapping[obj[0]]!,
              obj[1]
            ]) // maps card names to oracle_ids
        .toList();

    tokenRepository.saveTokenList(tokens, cardTokenMapping);

    await cardRepository
        .populateCardsTable(cards, scryfallMetadata)
        .then((val) async {
      // Clear prompted dates since we just updated
      await _releaseDateHelper.clearPassedDates();

      _changeNotifier.markNeedsRefresh();
      if (context.mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          // If first time downloading, this will be only way to go back
          Navigator.of(context).pushNamedAndRemoveUntil("/", (route) => false);
        }
      }
    });
  }
}
