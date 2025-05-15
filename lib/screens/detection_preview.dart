import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;

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
  List<Detection> detections;
  _detectionPreviewState(this.image, this.detections);

  late Uint8List imagePng;
  List<Card> allCards = [];
  final ScrollController _scrollController = ScrollController();
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();

  @override
  void initState() {
    super.initState();
    detections.sort((a,b) => a.ocrDistance! - b.ocrDistance!);
    _deckStorage.getAllCards().then((value) => setState(() {allCards = value;}));
    imagePng = img.encodePng(image);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: detections.isEmpty ?
        Container(
          padding: EdgeInsets.all(50),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Spacer(flex: 7),
              Text("No card titles detected", style: TextStyle(fontSize: 20), textAlign: TextAlign.center,),
              Spacer(flex: 1),
              Text("Make sure the card titles are visible and at least 32 pixels height. \nYou can use the button with the picture icon to preview the picture taken",
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.white38,
                ),
                textAlign: TextAlign.center,
              ),
              Spacer(flex: 5)
            ],
          )
        )
      :
      ListView.separated(
        controller: _scrollController,
        separatorBuilder: (context, index) => Divider(indent: 10, endIndent: 10,),
        padding: EdgeInsets.all(5),
        itemCount: detections.length,
        itemBuilder: (context, index) {
          return Dismissible(
            confirmDismiss: confirmDeletion,
            key: UniqueKey(),
            background: Container(color: Colors.red,),
            onDismissed: (direction) {
              setState(() {
                detections.removeAt(index);
              });
            },
            child: Row(
              spacing: 15,
              children: [
                Text("${index + 1}"),
                Expanded(
                  flex: 1,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 30),
                      child: detections[index].textImage != null
                          ? Image.memory(img.encodePng(detections[index].textImage!))
                          : Text(""),
                    )
                ),
                Expanded(
                  flex: 1,
                  child: Autocomplete(
                    initialValue: TextEditingValue(text: detections[index].card.name),
                    optionsViewOpenDirection: OptionsViewOpenDirection.down,
                    optionsBuilder: (val) {
                      if (val.text == "") {
                        return const Iterable<String>.empty();
                      }
                      return allCards
                          .where((el) => el.name.toLowerCase().contains(val.text.toLowerCase()))
                          .map((el) => el.name)
                          .toList();
                    },
                    onSelected: (option) {
                      Card newCard = allCards.firstWhere((x) => x.name == option);
                      setState(() {
                        detections[index].card = newCard;
                      });
                      debugPrint(detections.map((x) => x.card.name).toList().toString());
                    },
                  )
                ),
              ],
            )
          );
        }
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: detections.isEmpty ? null : saveDetectionsToDeck,
        label: Text("Save Deck"),
        icon: Icon(Icons.save)
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(
              onPressed: () async {
                detections = [Detection(
                    card: allCards.firstWhere((x) => x.name == "Black Lotus"),
                    ocrText: ""
                )] + detections;
                setState(() {});
                _scrollController
                    .animateTo(
                    _scrollController.position.minScrollExtent,
                      duration: const Duration(milliseconds: 500
                    ),
                  curve: Curves.easeOut
                );
              },
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

  void saveDetectionsToDeck() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            Center(child: CircularProgressIndicator()),
      ),
    );
    final deckId = await createDeckAndSave(detections.map((x) => x.card).toList());
    debugPrint("Deck saved with id: $deckId");
    final allDecks = await _deckStorage.getAllDecks();
    final newDeck = allDecks.where((x) => x.id == deckId).first;

    _changeNotifier.markNeedsRefresh();

    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => DeckViewer(deck: newDeck),
        ),
        ModalRoute.withName('/')
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
              child: Image.memory(imagePng)
          );
        }
    );
  }

  Future<int> createDeckAndSave(List<Card> matchedCards) async {
    final DateTime dateTime = DateTime.now();
    return await _deckStorage.saveNewDeck(dateTime, matchedCards);
  }

  Future<bool> confirmDeletion(direction) async {
    return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("Confirm"),
        content: const Text("Are you sure you wish to delete this item?"),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("DELETE")
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("CANCEL"),
          ),
        ],
      );
    },
    );
  }
}