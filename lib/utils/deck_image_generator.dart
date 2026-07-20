import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/data/models/deck.dart';
import '/data/models/card.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/cube_repository.dart';

SetRepository setRepository = SetRepository();
CubeRepository cubeRepository = CubeRepository();

// Layout of Page
const imageWidth = 2000;
const int pageHeaderMargin = 357;
const int pageMargin = 25;
const int cardMargin = 8;
const int nCol = 6;

// Card Measurements
const double cardAspectRatio = 2.5 / 3.5;
int cardWidth = (imageWidth - 2 * pageMargin - (nCol - 1) * cardMargin) ~/ nCol;
int cardHeight = cardWidth ~/ cardAspectRatio;
int cardStackOffset = cardHeight ~/ 8.5;

Future<Image> generateDeckImage(Deck deck) async {
  final cardCandidates = deck.cards
      .where((card) => card.isCreature() || card.isNoncreatureSpell())
      .toList();
  final artUri = cardCandidates[Random().nextInt(cardCandidates.length)].imageUri!
      .replaceAll("normal", "art_crop");

  // Fire all independent async work in parallel
  final bgFuture = _loadAsset("assets/decklist_sharing/background_gradient.png");
  final brandingFuture = _loadAsset("assets/decklist_sharing/madeby_2.png");
  final artCropFuture = _loadNetworkImage(artUri);
  final diceFuture = _loadDice();
  final cardImageMapFuture = _loadAllCardImages(deck.cards);
  final prefsFuture = SharedPreferences.getInstance();
  final setsFuture = setRepository.getAllSets();
  final cubesFuture = cubeRepository.getAllCubes();

  final bgImage = await bgFuture;
  final brandingImage = await brandingFuture;
  final artCropImage = await artCropFuture;
  final diceImages = await diceFuture;
  final cardImageMap = await cardImageMapFuture;
  final prefs = await prefsFuture;
  final allSets = await setsFuture;
  final allCubes = await cubesFuture;

  final bool isSmallDeck = deck.cards.length <= 15;
  final smallNCol = 5;

  if (isSmallDeck) {
    cardWidth = (imageWidth - 2 * pageMargin - (smallNCol - 1) * cardMargin) ~/ smallNCol;
    cardHeight = cardWidth ~/ cardAspectRatio;
    cardStackOffset = cardHeight ~/ 8.5;
  }

  final totalHeight = isSmallDeck
      ? _computeSmallDeckHeight(deck.cards.length)
      : _computeLargeDeckHeight(deck.cards);

  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imageWidth.toDouble(), totalHeight.toDouble()));

  // Background gradient
  canvas.drawImage(bgImage, Offset.zero, Paint());

  // White header rect
  canvas.drawRect(
    Rect.fromLTWH(0, 0, imageWidth.toDouble(), pageHeaderMargin.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );

  // Art crop — some images have a different aspect ratio than standard cards
  final artDstW = (pageHeaderMargin * 571 ~/ 460).toDouble();
  final artCropH = (artCropImage.width * 460 ~/ 571).toDouble();
  final artSrcRect = Rect.fromLTWH(
    0,
    (artCropImage.height - artCropH) / 2,
    artCropImage.width.toDouble(),
    artCropH,
  );
  canvas.drawImageRect(
    artCropImage,
    artSrcRect,
    Rect.fromLTWH(0, 0, artDstW, pageHeaderMargin.toDouble()),
    Paint(),
  );
  _drawVignette(canvas, 0, 0, artDstW, pageHeaderMargin.toDouble());

  // Diagonal white triangle separating art crop from header text
  final path = Path()
    ..moveTo(artDstW, 0)
    ..lineTo(artDstW, pageHeaderMargin.toDouble())
    ..lineTo(artDstW - 50, pageHeaderMargin.toDouble())
    ..close();
  canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));

  // Deck name
  canvas.drawParagraph(
    _buildParagraph(deck.name ?? "Draft Deck", 90, FontWeight.w700),
    const Offset(475, 30),
  );

  // Deck metadata
  final username = prefs.getString("username");
  final usernameString = username != null ? "Drafter: $username" : "";

  final set = allSets.firstWhereOrNull((s) => s.code == deck.setId);
  final cube = allCubes.firstWhereOrNull((c) => c.cubecobraId == deck.cubecobraId);
  String setCubeString = "";
  if (set != null) {
    setCubeString = "Set: ${set.name}";
  } else if (cube != null) {
    setCubeString = "Cube: ${cube.name}";
  }

  String metaString = usernameString;
  metaString += deck.winLoss != null ? "\nRecord: ${deck.winLoss}" : "";
  metaString += "\n$setCubeString";

  canvas.drawParagraph(
    _buildParagraph(metaString, 36, FontWeight.w400),
    const Offset(490, 175),
  );

  // Branding image
  const edgePadding = 50;
  final qrHeight = (pageHeaderMargin - 2 * edgePadding).toDouble();
  canvas.drawImageRect(
    brandingImage,
    Rect.fromLTWH(0, 0, brandingImage.width.toDouble(), brandingImage.height.toDouble()),
    Rect.fromLTWH(
      imageWidth - 2 * qrHeight - edgePadding + 35,
      edgePadding + 65,
      2 * qrHeight,
      qrHeight,
    ),
    Paint(),
  );

  // Draw cards
  if (isSmallDeck) {
    _drawSmallDeckCards(canvas, deck, cardImageMap, smallNCol);
  } else {
    _drawLargeDeckCards(canvas, deck, cardImageMap, diceImages);
  }

  final picture = recorder.endRecording();
  final result = await picture.toImage(imageWidth, totalHeight);

  // Dispose all intermediate images
  bgImage.dispose();
  brandingImage.dispose();
  artCropImage.dispose();
  for (final img in diceImages) {
    img.dispose();
  }
  for (final img in cardImageMap.values) {
    img.dispose();
  }

  return result;
}

void _drawSmallDeckCards(Canvas canvas, Deck deck, Map<Card, Image> cardImageMap, int smallNCol) {
  final creatures = deck.cards
      .where((card) => card.type.contains("Creature"))
      .sorted((a, b) => a.manaValue.toInt() - b.manaValue.toInt())
      .toList();
  final nonCreatures = deck.cards
      .where((card) => !card.type.contains("Creature") && !card.type.contains("Land"))
      .sorted((a, b) => a.manaValue.toInt() - b.manaValue.toInt())
      .toList();
  final lands = deck.cards
      .where((card) => card.type.contains("Land"))
      .sorted((a, b) => a.manaValue.toInt() - b.manaValue.toInt())
      .toList();
  final cards = creatures + nonCreatures + lands;

  int row = 0;
  int col = 0;
  for (int i = 0; i < cards.length; i++) {
    final cardImage = cardImageMap[cards[i]]!;
    _drawCard(canvas, cardImage, col, 0, yOffset: row * (10 + cardHeight));
    col++;
    if (col == smallNCol && i < cards.length - 1) {
      col = 0;
      row++;
    }
  }
}

({Map<String, List<Card>> creatures, Map<String, List<Card>> noncreatures, List<Card> nonBasicLands, List<Card> basics})
    _classifyCards(List<Card> cards) {
  final creatures = <String, List<Card>>{
    "0-1": [], "2": [], "3": [], "4": [], "5": [], "6+": [],
  };
  final noncreatures = <String, List<Card>>{
    "0-1": [], "2": [], "3": [], "4": [], "5": [], "6+": [],
  };
  final nonBasicLands = <Card>[];
  final basics = <Card>[];

  const basicNames = ['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'];

  for (final card in cards) {
    if (card.isCreature()) {
      creatures[_manaKey(card.manaValue)]!.add(card);
    } else if (card.isNoncreatureSpell()) {
      noncreatures[_manaKey(card.manaValue)]!.add(card);
    } else if (card.isNonBasicLand()) {
      nonBasicLands.add(card);
    } else if (basicNames.contains(card.name)) {
      basics.add(card);
    }
  }

  basics.sort((a, b) => basicNames.indexOf(a.name).compareTo(basicNames.indexOf(b.name)));

  return (creatures: creatures, noncreatures: noncreatures, nonBasicLands: nonBasicLands, basics: basics);
}

String _manaKey(int manaValue) {
  if (manaValue > 5) return "6+";
  if (manaValue < 2) return "0-1";
  return manaValue.toString();
}

int _computeSmallDeckHeight(int numCards) {
  final nCol = 5;
  final rows = (numCards + nCol - 1) ~/ nCol - 1;
  return pageHeaderMargin + (rows + 1) * (cardHeight + 10) + 75;
}

int _computeLargeDeckHeight(List<Card> cards) {
  final classification = _classifyCards(cards);
  final maxStackCreatures = classification.creatures.values.map((v) => v.length).fold(0, max);
  final maxStackNonCreatures = classification.noncreatures.values.map((v) => v.length).fold(0, max);
  final landsOffsetY = 2 * cardHeight + (maxStackCreatures + maxStackNonCreatures) * cardStackOffset;
  return pageHeaderMargin + landsOffsetY + cardHeight + 75;
}

void _drawLargeDeckCards(Canvas canvas, Deck deck, Map<Card, Image> cardImageMap, List<Image> diceImages) {
  final classification = _classifyCards(deck.cards);
  final creatures = classification.creatures;
  final noncreatures = classification.noncreatures;
  final nonBasicLands = classification.nonBasicLands;
  final basics = classification.basics;

  final maxStackCreatures = creatures.values.map((v) => v.length).fold(0, max);
  final maxStackNonCreatures = noncreatures.values.map((v) => v.length).fold(0, max);

  // Creature Curve
  int row = 0;
  for (final bucket in creatures.values) {
    int k = 0;
    for (final card in bucket) {
      _drawCard(canvas, cardImageMap[card]!, row, k);
      k++;
    }
    row++;
  }

  // NonCreature Curve
  row = 0;
  for (final bucket in noncreatures.values) {
    int k = 0;
    for (final card in bucket) {
      _drawCard(canvas, cardImageMap[card]!, row, k,
        yOffset: cardHeight + maxStackCreatures * cardStackOffset);
      k++;
    }
    row++;
  }

  // NonBasic Lands
  int landsOffsetY = 2 * cardHeight + (maxStackCreatures + maxStackNonCreatures) * cardStackOffset;
  int j = 0;
  for (final card in nonBasicLands) {
    _drawCard(canvas, cardImageMap[card]!, 0, 0,
      yOffset: landsOffsetY,
      xOffset: j * (cardStackOffset * 1.5).floor(),
    );
    j++;
  }

  // Basic Lands
  final basicCounts = basics.groupFoldBy((el) => el, (int? previous, element) => (previous ?? 0) + 1);
  const edgePadding = 50;
  j = 0;
  final numBasics = basicCounts.length;
  final initialOffsetX = imageWidth - edgePadding - cardWidth - (numBasics - 1) * (cardWidth ~/ 2);

  for (final card in basicCounts.keys) {
    final count = basicCounts[card]!;
    final dice = <int>[];
    int remainder = count;
    while (dice.sum < count) {
      if (remainder > 6) {
        dice.add(6);
        remainder -= 6;
      } else {
        dice.add(remainder);
      }
    }

    final xOffset = initialOffsetX + (cardWidth ~/ 2) * j;
    _drawCard(canvas, cardImageMap[card]!, 0, 0,
      yOffset: landsOffsetY,
      xOffset: xOffset,
    );

    for (int i = 0; i < dice.length; i++) {
      int diceOffsetX = initialOffsetX + (cardWidth ~/ 2) * j + cardWidth ~/ 5;
      if (j == basicCounts.length - 1) {
        diceOffsetX = initialOffsetX + (cardWidth ~/ 2) * j + cardWidth ~/ 2.4;
      }

      final diceImg = diceImages[dice[i] - 1];
      canvas.drawImageRect(
        diceImg,
        Rect.fromLTWH(0, 0, diceImg.width.toDouble(), diceImg.height.toDouble()),
        Rect.fromLTWH(
          diceOffsetX.toDouble(),
          (pageHeaderMargin + landsOffsetY + cardHeight ~/ 3 + i * cardWidth ~/ 2.5).toDouble(),
          (cardWidth ~/ 3).toDouble(),
          (cardWidth ~/ 3).toDouble(),
        ),
        Paint(),
      );
    }
    j++;
  }
}

void _drawCard(Canvas canvas, Image card, int row, int k, {int yOffset = 0, int xOffset = 0}) {
  final dstX = (pageMargin + (cardWidth + cardMargin) * row + xOffset).toDouble();
  final dstY = (pageHeaderMargin + 50 + cardStackOffset * k + yOffset).toDouble();
  final dstRect = Rect.fromLTWH(dstX, dstY, cardWidth.toDouble(), cardHeight.toDouble());
  final rrect = RRect.fromRectAndRadius(dstRect, Radius.circular(cardHeight / 27));

  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawImageRect(
    card,
    Rect.fromLTWH(0, 0, card.width.toDouble(), card.height.toDouble()),
    dstRect,
    Paint(),
  );
  canvas.restore();
}

void _drawVignette(Canvas canvas, double x, double y, double w, double h) {
  final center = Offset(x + w / 2, y + h / 2);
  final radius = max(w, h) * 0.7;

  canvas.drawRect(
    Rect.fromLTWH(x, y, w, h),
    Paint()
      ..shader = Gradient.radial(
        center,
        radius,
        [const Color(0x00000000), const Color(0xCC000000)],
        [0.3, 1.0],
      ),
  );
}

Paragraph _buildParagraph(String text, double fontSize, FontWeight weight) {
  final builder = ParagraphBuilder(ParagraphStyle(
    fontFamily: 'Roboto',
    fontSize: fontSize,
    fontWeight: weight,
    maxLines: 3,
  ))
    ..pushStyle(TextStyle(color: const Color(0xFF000000)))
    ..addText(text);

  final paragraph = builder.build()
    ..layout(ParagraphConstraints(width: 1200));

  return paragraph;
}

Future<Image> _loadNetworkImage(String uri) async {
  final Uint8List bytes = (await NetworkAssetBundle(Uri.parse(uri))
      .load(uri))
      .buffer
      .asUint8List();

  return _decodeImage(bytes);
}

Future<Image> _loadCardImage(Card card) async {
  return _loadNetworkImage(card.imageUri!);
}

Future<Map<Card, Image>> _loadAllCardImages(List<Card> cards) async {
  final futures = <Future<Image>>[];
  for (final card in cards) {
    futures.add(_loadCardImage(card));
  }
  final images = await Future.wait(futures);
  final map = <Card, Image>{};
  for (int i = 0; i < cards.length; i++) {
    map[cards[i]] = images[i];
  }
  return map;
}

Future<List<Image>> _loadDice() async {
  return Future.wait([1, 2, 3, 4, 5, 6]
      .map((el) => _loadAsset("assets/app_icons/dice/dice$el.png")));
}

Future<Image> _loadAsset(String path) async {
  final data = await rootBundle.load(path);
  return _decodeImage(data.buffer.asUint8List());
}

Future<Image> _decodeImage(Uint8List bytes) async {
  final buffer = await ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}
