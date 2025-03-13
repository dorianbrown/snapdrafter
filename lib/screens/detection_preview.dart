import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'deck_viewer.dart';
import '/utils/data.dart';
import '/utils/models.dart';

DeckStorage _deckStorage = DeckStorage();

class DetectionPreviewScreen extends StatelessWidget {
  final img.Image image;
  final List<Card> matchedCards;

  const DetectionPreviewScreen(
    {super.key, required this.image, required this.matchedCards});

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
          final deckId = await createDeckAndSave(matchedCards);
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => DeckViewer(deckId: deckId),
            ),
            ModalRoute.withName('/')
          );
        },
        label: Text("Save Deck"),
        icon: Icon(Icons.add)),
    );
  }

  Future<int> createDeckAndSave(List<Card> matchedCards) async {
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveNewDeck(dateTime, matchedCards);
  }
}