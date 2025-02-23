import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  // TODO: We need to track totalBytes and actualBytes separately
  ValueNotifier downloadProgressNotifier = ValueNotifier(0);

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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "Downloading Scryfall Card Data",
                    style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.w600,
                    )
                  ),
                  const SizedBox(
                    height: 32,
                  ),
                  LinearProgressIndicator(
                    value: double.parse(downloadProgressNotifier.value.toString()) / 100,
                  ),
                  const SizedBox(
                    height: 32,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  Text(
                    "${downloadProgressNotifier.value}%",
                    style: const TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.w600,
                        color: Colors.black),
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
    await Dio().download(
        // TODO: Use https://api.scryfall.com/bulk-data to get correct download link
        "https://data.scryfall.io/unique-artwork/unique-artwork-20250223100404.json",
        '${directory.path}/scryfall-card-data.json',
        onReceiveProgress: (actualBytes, int totalBytes) {
          // TODO: If totalBytes == -1, then we need to show #mB downloaded instead of current
          downloadProgressNotifier.value = (actualBytes / totalBytes * 100).floor();
        });
    debugPrint('File downloaded at ${directory.path}/samplePDF.pdf');
  }

}