import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import '/widgets/deck_viewer.dart';
import '/utils/data.dart';
import '/utils/models.dart' as models;

DeckStorage _deckStorage = DeckStorage();

class DetectionPreviewScreen extends StatelessWidget {
  final img.Image image;
  final List<String> detections;

  const DetectionPreviewScreen(
      {super.key, required this.image, required this.detections});

  @override
  Widget build(BuildContext context) {
    final viewTransformationController = TransformationController();
    final zoomFactor = 0.1;
    final xTranslate = 0.0;
    final yTranslate = 200.0;
    viewTransformationController.value.setEntry(0, 0, zoomFactor);
    viewTransformationController.value.setEntry(1, 1, zoomFactor);
    viewTransformationController.value.setEntry(2, 2, zoomFactor);
    viewTransformationController.value.setEntry(0, 3, xTranslate);
    viewTransformationController.value.setEntry(1, 3, yTranslate);
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: Center(
          child: InteractiveViewer(
              constrained: false,
              clipBehavior: Clip.none,
              minScale: 0.1,
              maxScale: 0.5,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              transformationController: viewTransformationController,
              child: Image.memory(img.encodePng(image))
          )
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    Center(child: CircularProgressIndicator()),
              ),
            );
            final deckId = await createDeckAndSave(detections);
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => DeckViewer(deckId: deckId),
                ),
                ModalRoute.withName('/'));
            // Make sure to adjust route to go back to 'My Decks'
          },
          label: Text("Save Deck"),
          icon: Icon(Icons.add)),
    );
  }

  Future<int> createDeckAndSave(List<String> detections) async {
    final allCards = await _deckStorage.getAllCards();
    final choices = allCards.map((card) => card.title).toList();
    final List<models.Card> matchedCards = [];
    debugPrint("Matching detections with database");
    for (final detection in detections) {
      final match = extractOne(query: detection, choices: choices);
      debugPrint(match.toString());
      debugPrint(allCards[match.index].toString());
      matchedCards.add(allCards[match.index]);
    }
    final String deckName = "Draft Deck";
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveDeck(deckName, dateTime, matchedCards);
  }
}