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
  final List<Detection> detections;
  _detectionPreviewState(this.image, this.detections);

  late Uint8List imagePng;
  List<Card> allCards = [];
  ScrollController _scrollController = new ScrollController();

  @override
  void initState() {
    super.initState();
    _deckStorage.getAllCards().then((value) => setState(() {allCards = value;}));
    imagePng = img.encodePng(image);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection Preview')),
      body: ListView.separated(
        controller: _scrollController,
        separatorBuilder: (context, index) => Divider(indent: 10, endIndent: 10,),
        padding: EdgeInsets.all(5),
        itemCount: detections.length,
        itemBuilder: (context, index) {
          return Dismissible(
            key: UniqueKey(),
            background: Container(color: Colors.red,),
            onDismissed: (direction) {
              // FIXME: When removing 25, then 26, using the index for removal causes issues
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
                if (kDebugMode)
                  Expanded(
                    flex: 1,
                    child: Text(detections[index].ocrText, style: TextStyle(height: 1.1),)
                  ),
                Expanded(
                  flex: 1,
                  child: Autocomplete(
                    initialValue: TextEditingValue(text: detections[index].card.name),
                    optionsViewOpenDirection: OptionsViewOpenDirection.up,
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
              onPressed: () async {
                detections.add(Detection(
                  card: allCards.firstWhere((x) => x.name == "Fblthp, the Lost"),
                  ocrText: ""
                ));
                setState(() {});
                _scrollController
                    .animateTo(
                    _scrollController.position.extentTotal,
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
}