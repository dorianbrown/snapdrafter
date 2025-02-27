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
    // Make this handle image dimensions. Zoom depends on image resolution
    final scaleMatrix = Matrix4.identity()..scale(0.8);
    final viewTransformationController = TransformationController(scaleMatrix);
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: Center(
          child: InteractiveViewer(
              // TODO: Fix this behavior, start at right zoom level, and set correct zoom constraints
              // constrained: false,
              clipBehavior: Clip.none,
              minScale: 0.3,
              maxScale: 1,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              transformationController: viewTransformationController,
              // alignment: Alignment.center,
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