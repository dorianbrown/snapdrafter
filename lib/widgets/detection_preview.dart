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
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: Center(
          child: LayoutBuilder(
              builder: (context, constraints) {
                double aspectRatio = image.width / image.height;
                double translationY = 0.5*(constraints.maxHeight - (constraints.maxWidth / aspectRatio));
                double minScale = constraints.maxWidth / image.width;
                final scaleMatrix = Matrix4.identity()..scale(minScale);
                scaleMatrix.setEntry(1, 3, translationY);
                final viewTransformationController = TransformationController(scaleMatrix);
                return InteractiveViewer(
                    constrained: false,
                    clipBehavior: Clip.none,
                    minScale: minScale,
                    maxScale: 1,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    transformationController: viewTransformationController,
                    child: Image.memory(img.encodePng(image))
                );
              }
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
      debugPrint("Matching $detection with database");
      final match = extractOne(query: detection, choices: choices);
      debugPrint(match.toString());
      debugPrint(allCards[match.index].toString());
      matchedCards.add(allCards[match.index]);
    }
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveNewDeck(dateTime, matchedCards);
  }
}