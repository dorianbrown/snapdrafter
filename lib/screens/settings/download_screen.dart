import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:http/http.dart' as http;

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
import '/utils/release_date_helper.dart';
import '/utils/printing_selector.dart';
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
            .where((x) => x["type"] == "unique_artwork")
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

    // Keeps the best overall printing and the first (original) printing per
    // oracle id, so only a single card per oracle id is stored. Challengers
    // are compared against the stored records without allocating new ones.
    void considerEntry(Map<String, dynamic> acc, Map<dynamic, dynamic> val) {
      final best = acc["best"] as Map<String, dynamic>?;
      if (best == null ||
          PrintingSelector.compareRawToRecord(val, best) < 0) {
        acc["best"] = PrintingSelector.entryRecord(val);
      }
      if (PrintingSelector.isExcludedFromFirstPrinting(val)) return;
      final first = acc["first"] as Map<String, dynamic>?;
      if (first == null ||
          PrintingSelector.compareFirstPrintingRawToRecord(val, first) < 0) {
        acc["first"] = PrintingSelector.entryRecord(val);
      }
    }

    final releaseNoticeCutoff = convertDatetimeToYMD(DateTime.now()
        .add(const Duration(days: SetRepository.releaseNoticeDays)));
    List<Card> cards = [];
    List<Token> tokens = [];
    Map<String, Map<String, dynamic>> cardAccumulators = {};
    Map<String, Map<String, dynamic>> tokenAccumulators = {};
    List<List<String>> cardTokenMapping = [];
    Map<String, String> nameOracleMapping = {};
    String newestRelease = "1900-01-01";
    Map<String, Map<String, String>> downloadedSets = {};
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
      // Record every set seen in the bulk data, including unreleased
      // (prerelease) sets, so the app knows its cards are already downloaded.
      final setCode = val["set"];
      final setReleasedAt = val["released_at"];
      if (setCode is String &&
          setReleasedAt is String &&
          setReleasedAt.isNotEmpty) {
        downloadedSets[setCode] = {
          "name": val["set_name"] as String? ?? setCode,
          "released_at": setReleasedAt,
        };
      }
      // Playable Card
      if (validCardLayouts.contains(val["layout"])) {
        if (val["card_faces"] == null && val["image_uris"] == null) return;
        final imageUri = PrintingSelector.extractImageUri(val);
        if (imageUri == null) return;
        if (newestRelease.compareTo(val["released_at"]) < 0 &&
            val["released_at"].compareTo(releaseNoticeCutoff) < 0 &&
            ["expansion", "core", "masters"].contains(val["set_type"]) &&
            val["digital"] != true) {
          newestRelease = val["released_at"];
          scryfallMetadata["newest_set_name"] = val["set_name"];
        }
        nameOracleMapping[val["name"]] = val["oracle_id"];
        final oracleId = val["oracle_id"];
        var acc = cardAccumulators[oracleId];
        if (acc == null) {
          acc = {
            "oracle_id": oracleId,
            "oracle": PrintingSelector.oracleFields(val)
          };
          cardAccumulators[oracleId] = acc;
        }
        considerEntry(acc, val);
      }
      // Tokens
      if (val["layout"] == "token") {
        if (val["all_parts"] == null || val["all_parts"].isEmpty) return;
        if (PrintingSelector.extractImageUri(val) == null) return;
        List<Map<String, dynamic>> allParts = val["all_parts"]
            .whereType<Map<String, dynamic>>()
            .where((obj) => obj["component"] == "combo_piece")
            .toList();
        final oracleId = val["oracle_id"];
        var acc = tokenAccumulators[oracleId];
        if (acc == null) {
          acc = {"oracle_id": oracleId, "name": val["name"]};
          tokenAccumulators[oracleId] = acc;
          cardTokenMapping.addAll(allParts
              .map((obj) => [obj["name"] as String, oracleId]));
        }
        considerEntry(acc, val);
      }
    }, onDone: () {
      completer.complete();
    });
    await completer.future;

    if (downloadedSets.isNotEmpty) {
      await setRepository.saveDownloadedSets(downloadedSets);
    }

    for (final acc in cardAccumulators.values) {
      final oracle = acc["oracle"] as Map<String, dynamic>;
      final best = acc["best"] as Map<String, dynamic>;
      final first = acc["first"] as Map<String, dynamic>?;
      cards.add(Card(
          scryfallId: best["scryfall_id"] as String,
          oracleId: acc["oracle_id"] as String,
          name: oracle["name"] as String,
          title: oracle["title"] as String,
          type: oracle["type"] as String,
          colors: oracle["colors"] as String?,
          imageUri: best["image_uri"] as String,
          firstPrintingImageUri: first?["image_uri"] as String?,
          manaCost: oracle["mana_cost"] as String?,
          manaValue: oracle["mana_value"] as int,
          producedMana: oracle["produced_mana"] as String?,
          oracleText: oracle["oracle_text"] as String?));
    }

    for (final acc in tokenAccumulators.values) {
      final best = acc["best"] as Map<String, dynamic>;
      final first = acc["first"] as Map<String, dynamic>;
      tokens.add(Token(
        oracleId: acc["oracle_id"] as String,
        name: acc["name"] as String,
        imageUri: best["image_uri"] as String,
        firstPrintingImageUri: first["image_uri"] as String?,
      ));
    }

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
