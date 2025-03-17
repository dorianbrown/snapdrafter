import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'deck_viewer.dart';
import '/utils/data.dart';
import '/utils/models.dart';

DeckStorage _deckStorage = DeckStorage();

class DetectionPreviewScreen extends StatefulWidget {
  final img.Image image;
  final List<Detection> detections;

  const DetectionPreviewScreen(
      {super.key, required this.image, required this.detections});

  @override
  _detectionPreviewState createState() => _detectionPreviewState(image, detections);
}

class _detectionPreviewState extends State<DetectionPreviewScreen> {
  final img.Image image;
  final List<Detection> detections;
  _detectionPreviewState(this.image, this.detections);

  late List<Card> matchedCards;
  List<Card> allCards = [];

  @override
  void initState() {
    super.initState();
    matchedCards = detections.map((x) => x.card).toList();
    _deckStorage.getAllCards().then((value) => setState(() {allCards = value;}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: ListView.separated(
        separatorBuilder: (context, index) => Divider(indent: 10, endIndent: 10,),
        padding: EdgeInsets.all(5),
        itemCount: detections.length,
        itemBuilder: (context, index) {
          return Row(
            spacing: 15,
            children: [
              Text("${index + 1}"),
              Expanded(
                flex: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 30),
                    child: Image.memory(
                      img.encodePng(detections[index].textImage),
                    ),
                  )
              ),
              Expanded(
                flex: 1,
                child: Text(detections[index].ocrText, style: TextStyle(height: 1.1),)
              ),
              Expanded(
                flex: 1,
                child: DropdownButton(
                  value: matchedCards.isNotEmpty ? matchedCards[index].name : null,
                  items: allCards.isNotEmpty ? allCards.map((x) => DropdownMenuItem(
                    value: x.name,
                    child: Text(x.name),
                  )).toList() : [],
                  onChanged: null
                )
              ),
            ],
          );
        }
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  Center(child: CircularProgressIndicator()),
            ),
          );
          final deckId = await createDeckAndSave(detections.map((x) => x.card).toList());
          debugPrint("Deck saved with id: $deckId");
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => DeckViewer(deckId: deckId),
            ),
            ModalRoute.withName('/')
          );
        },
        label: Text("Save Deck"),
        icon: Icon(Icons.save)
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(
              onPressed: null,
              icon: Icon(Icons.add)
            ),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return Dialog(
                      child: createInteractiveViewer(image),
                    );
                  }
                );
              },
              icon: Icon(Icons.image)
            )
          ],
        ),
      ),
    );
  }

  LayoutBuilder createInteractiveViewer(img.Image image) {
    return LayoutBuilder(
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
    );
  }

  Future<int> createDeckAndSave(List<Card> matchedCards) async {
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveNewDeck(dateTime, matchedCards);
  }
}