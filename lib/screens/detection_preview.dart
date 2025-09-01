import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;

import 'deck_viewer.dart';
import '/models/detection.dart';
import '/utils/deck_change_notifier.dart';
import '/data/models/card.dart';
import '/data/repositories/card_repository.dart';
import '/data/repositories/deck_repository.dart';

CardRepository cardRepository = CardRepository();
DeckRepository deckRepository = DeckRepository();

class DetectionPreviewScreen extends StatefulWidget {
  final img.Image image;
  final img.Image originalImage;
  final List<Detection> detections;

  const DetectionPreviewScreen({
      super.key, 
      required this.image,
      required this.originalImage,
      required this.detections,
  });

  @override
  _detectionPreviewState createState() => _detectionPreviewState(image, originalImage, detections);
}

class _detectionPreviewState extends State<DetectionPreviewScreen> {
  final img.Image image;
  final img.Image originalImage;
  List<Detection> detections;
  _detectionPreviewState(this.image, this.originalImage, this.detections);

  late Uint8List imagePng;
  List<Card> allCards = [];
  final ScrollController _scrollController = ScrollController();
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();

  @override
  void initState() {
    super.initState();
    detections.sort((a,b) => a.ocrDistance! - b.ocrDistance!);
    cardRepository.getAllCards().then((value) => setState(() {allCards = value;}));
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
              Text("Make sure the cards are oriented in the upwards direction",
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
                    initialValue: TextEditingValue(text: detections[index].card?.name ?? ""),
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
                      debugPrint(detections.map((x) => x.card?.name ?? "").toList().toString());
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
                    card: null,
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
              onPressed: () => createInteractiveViewer(imagePng),
              icon: Icon(Icons.image)
            )
          ],
        ),
      ),
    );
  }

  void saveDetectionsToDeck() async {

    // Check that all cards are defined
    if (detections.map((x) => x.card).any((x) => x == null)) {
      // Communicate problem to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You have undefined cards, remove them first'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            Center(child: CircularProgressIndicator()),
      ),
    );
    
    final matchedCards = detections
        .where((detection) => detection.card != null)
        .map((detection) => detection.card!)
        .toList();
    
    final deckId = await createDeckAndSave(matchedCards, originalImage);
    debugPrint("Deck saved with id: $deckId");
    final allDecks = await deckRepository.getAllDecks();
    final newDeck = allDecks.where((x) => x.id == deckId).first;

    _changeNotifier.markNeedsRefresh();

    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => DeckViewer(deck: newDeck),
        ),
        ModalRoute.withName('/')
    );
  }

  void createInteractiveViewer(Uint8List imageBytes) {
    showDialog(
        context: context,
        builder: (innerContext) {
          return AlertDialog(
              insetPadding: EdgeInsets.zero, // Maximize viewing area
              contentPadding: EdgeInsets.zero, // Maximize viewing area
              actions: [
                TextButton(
                    style: ButtonStyle(
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                      backgroundColor: MaterialStateProperty.all(Colors.black38),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Back")
                ),
              ],
              content: Column(
                children: [
                  Expanded(
                      child: InteractiveViewer(
                          clipBehavior: Clip.none,
                          minScale: 1,
                          maxScale: 4,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          child: Image.memory(imagePng)
                      )
                  )
                ],
              )
          );
        }
    );
  }

  Future<int> createDeckAndSave(List<Card> matchedCards, img.Image image) async {
    final DateTime dateTime = DateTime.now();
    return await deckRepository.saveNewDeck(dateTime, matchedCards, image: image);
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
