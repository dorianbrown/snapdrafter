import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../utils/utils.dart';
import 'deck_viewer.dart';
import 'image_processing_screen.dart';
import '/models/detection.dart';
import '/utils/deck_change_notifier.dart';
import '/data/models/card.dart';
import '/data/models/deck.dart';
import '/data/models/deck_upsert.dart';
import '/data/repositories/card_repository.dart';
import '/data/repositories/deck_repository.dart';

CardRepository cardRepository = CardRepository();
DeckRepository deckRepository = DeckRepository();

class DetectionPreviewScreen extends StatefulWidget {
  final img.Image image;
  final img.Image originalImage;
  final List<Detection> detections;
  final CaptureSource captureSource;
  final DeckUpsert? baseDeck;
  final img.Image? baseDeckImage;
  final bool isSideboardStep;

  const DetectionPreviewScreen({
      super.key, 
      required this.image,
      required this.originalImage,
      required this.detections,
      this.captureSource = CaptureSource.gallery,
      this.baseDeck,
      this.baseDeckImage,
      this.isSideboardStep = false,
  });

  @override
  _detectionPreviewState createState() => _detectionPreviewState();
}

class _detectionPreviewState extends State<DetectionPreviewScreen> {
  late img.Image image;
  late img.Image originalImage;
  late List<Detection> detections;
  late Uint8List imagePng;
  List<Card> allCards = [];
  final ScrollController _scrollController = ScrollController();
  final DeckChangeNotifier _changeNotifier = DeckChangeNotifier();

  @override
  void initState() {
    super.initState();
    image = widget.image;
    originalImage = widget.originalImage;
    detections = List.from(widget.detections);
    detections.sort((a,b) => a.ocrDistance! - b.ocrDistance!);
    cardRepository.getAllCards().then((value) => setState(() {allCards = value;}));
    imagePng = img.encodePng(image);
  }

  void _onAddSideboard() async {
    // Validate all cards are defined
    if (detections.any((det) => det.card == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please define all cards before adding sideboard'),
        ),
      );
      return;
    }
    final matchedCards = detections
        .where((det) => det.card != null)
        .map((det) => det.card!)
        .toList();
    
    // Build baseDeck with mainboard
    final baseDeck = DeckUpsert(
      cards: matchedCards,
      sideboard: const [],
    );
    final img.Image? baseDeckImage = originalImage;

    switch (widget.captureSource) {
      case CaptureSource.gallery:
      case CaptureSource.share:
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => deckImageProcessing(
                filePath: image.path,
                captureSource: widget.captureSource,
                baseDeck: baseDeck,
                baseDeckImage: baseDeckImage,
                isSideboardStep: true,
              ),
            ),
          );
        }
        break;
      case CaptureSource.camera:
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.camera);
        if (image != null) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => deckImageProcessing(
                filePath: image.path,
                captureSource: widget.captureSource,
                baseDeck: baseDeck,
                baseDeckImage: baseDeckImage,
                isSideboardStep: true,
              ),
            ),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.isSideboardStep) {
          // Pop back to the mainboard preview
          Navigator.of(context).pop();
          return false;
        }
        // For non-sideboard steps, navigate back to home
        Navigator.of(context).popUntil(ModalRoute.withName('/'));
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isSideboardStep ? 'Sideboard Preview' : 'Detection Preview'),
          actions: widget.isSideboardStep ? null : [],
        ),
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
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isSideboardStep)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FloatingActionButton.extended(
                  heroTag: 'add_sideboard',
                  onPressed: _onAddSideboard,
                  label: const Text('Sideboard'),
                  icon: const Icon(Icons.add_box_rounded),
                ),
              ),
            FloatingActionButton.extended(
              heroTag: 'save_deck',
              onPressed: detections.isEmpty ? null : saveDetectionsToDeck,
              label: Text(widget.isSideboardStep ? "Save Deck + Sideboard" : "Save Deck"),
              icon: const Icon(Icons.save),
            ),
          ],
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
      ),
    );
  }

  void saveDetectionsToDeck() async {
    // Check that all cards are defined
    if (detections.any((x) => x.card == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You have undefined cards, remove them first'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Center(child: CircularProgressIndicator()),
      ),
    );
    
    final matchedCards = detections
        .where((detection) => detection.card != null)
        .map((detection) => detection.card!)
        .toList();
    
    final DeckUpsert upsert;
    final img.Image imageToUse;
    
    if (widget.isSideboardStep && widget.baseDeck != null) {
      // Sideboard step: combine mainboard from baseDeck with sideboard from matchedCards
      upsert = DeckUpsert(
        cards: widget.baseDeck!.cards,
        sideboard: matchedCards,
        name: widget.baseDeck!.name,
        winLoss: widget.baseDeck!.winLoss,
        setId: widget.baseDeck!.setId,
        cubecobraId: widget.baseDeck!.cubecobraId,
        ymd: widget.baseDeck!.ymd,
      );
      imageToUse = widget.baseDeckImage ?? originalImage;
    } else {
      // Main step (no sideboard) or baseDeck is null
      upsert = DeckUpsert(
        cards: matchedCards,
        sideboard: const [],
        name: null,
        winLoss: null,
        setId: null,
        cubecobraId: null,
        ymd: null,
      );
      imageToUse = originalImage;
    }
    
    final newDeck = await deckRepository.saveNewDeck(upsert, image: imageToUse);
    debugPrint("Deck saved with id: ${newDeck.id}");

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

  Future<Deck> createDeckAndSave(List<Card> matchedCards, img.Image image) async {
    return await deckRepository.saveNewDeck(
      DeckUpsert(cards: matchedCards, sideboard: const []),
      image: image,
    );
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
