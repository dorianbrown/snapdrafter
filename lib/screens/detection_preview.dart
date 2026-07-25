import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../utils/utils.dart';
import '../utils/card_matcher.dart';
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
  final DeckUpsert? prefill;
  final void Function(Deck)? onDeckSaved;

  const DetectionPreviewScreen({
      super.key, 
      required this.image,
      required this.originalImage,
      required this.detections,
      this.captureSource = CaptureSource.gallery,
      this.baseDeck,
      this.baseDeckImage,
      this.isSideboardStep = false,
      this.prefill,
      this.onDeckSaved,
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
    final img.Image baseDeckImage = originalImage;

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
          Navigator.of(context).pop();
          return false;
        }
        if (widget.onDeckSaved != null) {
          Navigator.of(context).popUntil(ModalRoute.withName('scan_deck'));
          Navigator.of(context).pop();
          return false;
        }
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
                Text("Try and make sure the titles are clearly visible",
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
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                '${detections.where((d) => d.card != null).length} of ${detections.length} cards matched',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                separatorBuilder: (context, index) => Divider(indent: 10, endIndent: 10,),
                padding: EdgeInsets.only(top: 10, bottom: 10),
                itemCount: detections.length,
                itemBuilder: (context, index) {
                  final detection = detections[index];
                  final score = detection.ocrDistance;
                  final statusColor = _statusColor(detection);

                  return Dismissible(
                    confirmDismiss: confirmDeletion,
                    key: UniqueKey(),
                    background: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        // borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: EdgeInsets.only(right: 20),
                      child: Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) {
                      setState(() {
                        detections.removeAt(index);
                      });
                    },
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Row(
                              children: [
                                SizedBox(width: 2,),
                                Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: detection.textImage != null
                                              ? ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.35,
                                              maxHeight: 32,
                                            ),
                                            child: Image.memory(
                                              img.encodePng(detection.textImage!),
                                              height: 32,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                              : SizedBox(width: 32, height: 32),
                                        ),
                                        SizedBox(width: 15),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: 4),
                                Autocomplete<String>(
                                  initialValue: TextEditingValue(text: detection.card?.name ?? ""),
                                  optionsViewOpenDirection: OptionsViewOpenDirection.down,
                                  optionsBuilder: (val) {
                                    if (val.text.isEmpty) {
                                      return const Iterable<String>.empty();
                                    }
                                    return searchCardNames(val.text, allCards);
                                  },
                                  onSelected: (option) {
                                    Card newCard = findCardByName(option, allCards)!;
                                    setState(() {
                                      detections[index].card = newCard;
                                    });
                                  },
                                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                                    return TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      onSubmitted: (value) => onSubmitted(),
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          border: UnderlineInputBorder(
                                          ),
                                          enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(color: Colors.white54)
                                          )
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (detection.ocrText.isNotEmpty)
                                      Text(
                                        '${detection.ocrText}: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).hintColor,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (score != null)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        child: Text(
                                          '$score%',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 10),
                        ],
                      ),
                    ),
                  );
                }
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isSideboardStep)
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: FloatingActionButton.extended(
                  heroTag: 'add_sideboard',
                  onPressed: _onAddSideboard,
                  label: const Text('Sideboard', style: TextStyle(fontSize: 13)),
                  icon: const Icon(Icons.add_box_rounded, size: 20),
                ),
              ),
            FloatingActionButton.extended(
              heroTag: 'save_deck',
              onPressed: detections.isEmpty ? null : saveDetectionsToDeck,
              label: Text(widget.isSideboardStep ? "Save Deck + Sideboard" : "Save",
                  style: TextStyle(fontSize: 13)),
              icon: const Icon(Icons.save, size: 20),
            ),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Add card',
                onPressed: () async {
                  detections = [Detection(
                      card: null,
                      ocrText: "",
                      x1: 0,
                      y1: 0,
                      x2: 0,
                      y2: 0,
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
                icon: Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'View image',
                onPressed: _openZoomViewer,
                icon: Icon(Icons.image),
              ),
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
        name: widget.prefill?.name ?? widget.baseDeck!.name,
        wins: widget.baseDeck!.wins,
        losses: widget.baseDeck!.losses,
        draws: widget.baseDeck!.draws,
        setId: widget.prefill?.setId ?? widget.baseDeck!.setId,
        cubecobraId: widget.prefill?.cubecobraId ?? widget.baseDeck!.cubecobraId,
        ymd: widget.baseDeck!.ymd,
      );
      imageToUse = widget.baseDeckImage ?? originalImage;
    } else {
      // Main step (no sideboard) or baseDeck is null
      upsert = DeckUpsert(
        cards: matchedCards,
        sideboard: const [],
        name: widget.prefill?.name ?? null,
        wins: null,
        losses: null,
        draws: null,
        setId: widget.prefill?.setId ?? null,
        cubecobraId: widget.prefill?.cubecobraId ?? null,
        ymd: null,
      );
      imageToUse = originalImage;
    }
    
    final newDeck = await deckRepository.saveNewDeck(upsert, image: imageToUse);
    debugPrint("Deck saved with id: ${newDeck.id}");

    _changeNotifier.markNeedsRefresh();

    if (widget.onDeckSaved != null) {
      Navigator.of(context).pop();
      widget.onDeckSaved!(newDeck);
      if (mounted) {
        Navigator.of(context)
            .popUntil(ModalRoute.withName('scan_deck'));
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => DeckViewer(deck: newDeck),
          ),
          ModalRoute.withName('/')
      );
    }
  }

  void _openZoomViewer() {
    showDialog(
        context: context,
        builder: (innerContext) {
          return AlertDialog(
              insetPadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              actions: [
                TextButton(
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      backgroundColor: WidgetStateProperty.all(Colors.black38),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Back")
                ),
              ],
              content: Column(
                mainAxisSize: MainAxisSize.min,
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

Color _statusColor(Detection d) {
  if (d.card == null) return Colors.grey;
  final score = d.ocrDistance ?? 0;
  if (score > 70) return Colors.green;
  if (score > 40) return Colors.amber;
  return Colors.redAccent;
}
