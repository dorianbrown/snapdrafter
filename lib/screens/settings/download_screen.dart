import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '/utils/utils.dart';
import '/utils/deck_change_notifier.dart';
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
  ValueNotifier downloadProgressNotifier = ValueNotifier(0);
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();
  int totalBytes = 0;
  bool isDownloading = false;
  late CardRepository cardRepository;
  late SetRepository setRepository;
  late TokenRepository tokenRepository;
  Map<String, dynamic>? scryfallMetadata;

  @override
  initState() {
    super.initState();
    cardRepository = CardRepository();
    setRepository = SetRepository();
    tokenRepository = TokenRepository();

    setRepository.populateSetsTable();
    setRepository.getScryfallMetadata().then((value) {
      scryfallMetadata = value;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final metadataStyle = TextStyle(
      fontStyle: FontStyle.italic,
      color: Theme.of(context).hintColor
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Scryfall Download')),
      body: Center(
        child: ValueListenableBuilder(
          valueListenable: downloadProgressNotifier,
          builder: (context, value, snapshot) {
            return Column(
              spacing: 25,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                    "Scryfall Card Data",
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.w600,
                    )
                ),
                if (scryfallMetadata != null)
                  Table(
                    columnWidths: {
                      0: FixedColumnWidth(120),
                      1: IntrinsicColumnWidth()
                    },
                    children: [
                      TableRow(
                        children: [
                          Text("Last download:", style: metadataStyle),
                          Text(scryfallMetadata?['datetime'] ?? 'None', style: metadataStyle)
                        ]
                      ),
                      TableRow(
                          children: [
                            Text("Latest set:", style: metadataStyle),
                            Text(scryfallMetadata?['newest_set_name'] ?? 'None', style: metadataStyle)
                          ]
                      ),
                    ],
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                  child: const Icon(Icons.file_download_outlined, size: 70)
                ),
                Padding(
                    padding: EdgeInsets.fromLTRB(50, 0, 50, 0),
                    child: LinearProgressIndicator(
                      value: totalBytes > 0
                          ? downloadProgressNotifier.value / totalBytes
                          : 0,
                    ),
                ),
                (isDownloading)
                  ? Text(
                    (totalBytes > 0)
                      ? (downloadProgressNotifier.value < totalBytes)
                        ? "${(downloadProgressNotifier.value / (1000 * 1000)).ceil()} MB downloaded"
                        : "Processing download..."
                      : "Querying Scryfall"
                    ,
                    style: const TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.w600),
                  )
                  : ElevatedButton(onPressed: () {
                    isDownloading = true;
                    downloadFileFromServer();
                    setState(() {});
                }, child: Text("Download Scryfall Data"))
              ],
            );
          }),
      )
    );
  }

  downloadFileFromServer() async {
    downloadProgressNotifier.value = 0;
    Directory directory = Directory("");
    if (Platform.isAndroid) {
      directory = (await getExternalStorageDirectory())!;
    } else {
      directory = (await getApplicationDocumentsDirectory());
    }

    final getResponse = await http.get(Uri.parse("https://api.scryfall.com/bulk-data"));
    String downloadUri;
    if (getResponse.statusCode == 200) {
      var responseMap = jsonDecode(getResponse.body);
      try {
        final dataMap = responseMap["data"]
            .where((x) => x["type"] == "oracle_cards")
            .toList()[0];
        downloadUri = dataMap["download_uri"];
        totalBytes = dataMap["size"];
      } on Exception catch (e) {
        throw Exception('Unable to connect to api.scryfall.com: $e');
      }
    } else {
      throw Exception('Unable to connect to api.scryfall.com. Status code: ${getResponse.statusCode}');
    }

    final downloadResponse = await Dio().get(
      downloadUri,
      options: Options(responseType: ResponseType.stream),
      onReceiveProgress: (actualBytes, int _) {
        downloadProgressNotifier.value = actualBytes;
      }
    );

    List<String> validCardLayouts = [
      "normal", "class", "saga", "meld", "prototype", "transform", "modal_dfc",
      "split", "adventure", "augment", "flip", "mutate", "case", "leveler"
    ];
    List<String> validTypes = [
      "Creature", "Artifact", "Enchantment", "Land", "Instant", "Sorcery",
      "Planeswalker", "Battle"
    ];

    mapToCard (Map val) {
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
        producedMana = val["card_faces"][0]["produced_mana"] ?? val["card_faces"][1]["produced_mana"];
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
          producedMana: producedMana
      );
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
    // This function allows us to parse elements from the stream, without
    // handling the entire json object. Might be a better way, but for now this
    // works.
    reviver (key, val) {
      // Playable Card
      if (val is Map && validCardLayouts.contains(val["layout"])) {
        if (val["card_faces"] == null && val["image_uris"] == null) {
          return null;
        }
        if (
          newestRelease.compareTo(val["released_at"]) < 0 &&
          // We add 8 days here to make set available for prereleases
          val["released_at"].compareTo(convertDatetimeToYMD(DateTime.now().add(Duration(days: 8)))) < 0 &&
          val["set_type"] == "expansion"
        ) {
          newestRelease = val["released_at"];
          scryfallMetadata["newest_set_name"] = val["set_name"];
        }

        nameOracleMapping[val["name"]] = val["oracle_id"];

        cards.add(mapToCard(val));
        return null;
      }
      // Tokens
      if (val is Map && val["layout"] == "token") {
        if (val["all_parts"] == null || val["all_parts"].isEmpty) {
          return null;
        }

        List<Map<String, dynamic>> allParts = val["all_parts"]
            .whereType<Map<String, dynamic>>()
            .where((obj) => obj["component"] == "combo_piece")
            .toList();
        cardTokenMapping.addAll(allParts.map((obj) => [obj["name"] as String, val["oracle_id"] as String]));

        tokens.add(
          Token(
            oracleId: val["oracle_id"],
            name: val["name"],
            imageUri: val["card_faces"] != null
              ? val["card_faces"][0]["image_uris"]["normal"]
              : val["image_uris"]["normal"],
          )
        );
        return null;
      }
      else {
        return val;
      }
    }

    final completer = Completer();
    downloadResponse.data.stream.cast<List<int>>()
        .transform(utf8.decoder)
        .transform(JsonDecoder(reviver))
        .listen(null, onDone: () {completer.complete();});
    await completer.future;

    debugPrint("tokenMapping: ${cardTokenMapping.length}");

    cardTokenMapping = cardTokenMapping
        .where((obj) => nameOracleMapping.keys.contains(obj[0]))  // Removes non-cards from mapping
        .map((obj) => [nameOracleMapping[obj[0]]!, obj[1]])  // maps card names to oracle_ids
        .toList();

    tokenRepository.saveTokenList(tokens, cardTokenMapping);

    await cardRepository.populateCardsTable(cards, scryfallMetadata).then((val) async {
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