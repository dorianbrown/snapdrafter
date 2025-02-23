import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// TODO: Check for wifi connection before downloading.

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  ValueNotifier downloadProgressNotifier = ValueNotifier(0);
  int totalBytes = 0;

  @override
  initState() {
    super.initState();
    downloadFileFromServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter File Download')),
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
                  Text(
                    (totalBytes > 0)
                      ? (downloadProgressNotifier.value < totalBytes)
                        ? "${(downloadProgressNotifier.value / (1000 * 1000)).ceil()} MB downloaded"
                        : "Download complete"
                      : "Querying Scryfall"
                    ,
                    style: const TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
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

    final response = await http.get(Uri.parse("https://api.scryfall.com/bulk-data"));
    String downloadUri;
    if (response.statusCode == 200) {
      var responseMap = jsonDecode(response.body);
      try {
        final dataMap = responseMap["data"]
            .where((x) => x["type"] == "unique_artwork")
            .toList()[0];
        downloadUri = dataMap["download_uri"];
        totalBytes = dataMap["size"];
      } on Exception catch (e) {
        throw Exception('Unable to connect to api.scryfall.com: $e');
      }
    } else {
      throw Exception('Unable to connect to api.scryfall.com. Status code: ${response.statusCode}');
    }

    String outputPath = '${directory.path}/scryfall-card-data.json';
    await Dio().download(
      downloadUri,
      outputPath,
      onReceiveProgress: (actualBytes, int _) {
        downloadProgressNotifier.value = actualBytes;
      }
    ).then((onValue) async {
      final file = await File(outputPath).readAsString();
      final rawDataMap = jsonDecode(file);
      // Parse rawData, then write to database
    });
    debugPrint('File downloaded at $outputPath');
  }

}