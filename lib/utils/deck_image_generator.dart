import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:image/image.dart';
import "package:collection/collection.dart";
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'data.dart';

DeckStorage deckStorage = DeckStorage();

// Layout of Page
const imageWidth = 4000;
const imageHeight = 6000;
const int pageHeaderMargin = 714;
const int pageMargin = 50;
const int cardMargin = 15;
const int stackSize = 4;
const int nCol = 6;

// Card Measurements
const double cardAspectRatio = 2.5 / 3.5;
const int cardWidth =
    (imageWidth - 2 * pageMargin - (nCol - 1) * cardMargin) ~/ nCol;
const int cardHeight = cardWidth ~/ cardAspectRatio;
const int cardStackOffset = cardHeight ~/ 8.5;

Future<Image> generateDeckImage(Deck deck) async {

  // Split into Creatures, Noncreature spells, and non-basic lands, sorted by
  // mana value
  final sortedCardImages = await getManaCurveImages(deck.cards);
  final creatures = sortedCardImages[0] as Map<String, List<Image>>;
  final nonCreatures = sortedCardImages[1] as Map<String, List<Image>>;
  final nonBasicLands = sortedCardImages[2] as List<Image>;

  List<String> basicNames = ['Plains', 'Island', 'Swamp', 'Mountain', 'Forest'];
  List<Card> basics = deck.cards
      .where((card) => basicNames.contains(card.name))
      .toList();

  basics.sort((a,b) => basicNames.indexOf(a.name).compareTo(basicNames.indexOf(b.name)));

  // Note that this assets can't be resized on the fly, required regenerating
  // zip file. So this should be done after all other measurements are final.
  final titleFontAsset = await rootBundle.load("assets/fonts/OpenSans-bold180.zip");
  final titleFont = BitmapFont.fromZip(titleFontAsset.buffer.asUint8List());
  final regularFontAsset = await rootBundle.load("assets/fonts/roboto-reg72.zip");
  final regularFont = BitmapFont.fromZip(regularFontAsset.buffer.asUint8List());

  Image deckImage = await decodeAsset("assets/decklist_sharing/background_gradient.png");

  // UI Elements (framing)
  deckImage = fillRect(deckImage,
      x1: 0,
      y1: 0,
      x2: imageWidth,
      y2: pageHeaderMargin,
      color: ColorRgb8(255, 255, 255)
  );

  // Art Crop dimensions 571x460
  List<Card> cardCandidates = deck.cards
      .where((card) => card.isCreature() || card.isNoncreatureSpell())
      .toList();
  String displayUri = cardCandidates[Random().nextInt(cardCandidates.length)].imageUri!;
  Image displayImage = await getImageFromUri(displayUri.replaceAll("normal", "art_crop"));

  // Some images have a different aspect ratio than standard cards
  displayImage = copyCrop(displayImage,
      x: 0,
      y: (displayImage.height - displayImage.width * 460 ~/ 571) ~/ 2,
      width: displayImage.width,
      height: displayImage.width * 460 ~/ 571
  );

  displayImage = copyResize(displayImage,
      height: pageHeaderMargin,
      width: pageHeaderMargin * 571 ~/ 460
  );

  displayImage = vignette(displayImage, start: 0.3, end: 0.9, amount: 0.8);

  deckImage = compositeImage(deckImage, displayImage,
    dstX: 0,
    dstY: 0,
  );

  // Diagonal line
  List<Point> vertices = [
    Point(displayImage.width, 0),
    Point(displayImage.width, pageHeaderMargin),
    Point(displayImage.width - 100, pageHeaderMargin),
  ];
  deckImage = fillPolygon(deckImage, vertices: vertices, color: ColorRgb8(255, 255, 255));

  // Title of Deck
  String deckNameString = deck.name ?? "Draft Deck";
  deckImage = drawString(
    deckImage,
    deckNameString,
    font: titleFont,
    x: 950,
    y: 30,
    color: ColorRgb8(0, 0, 0),
  );

  // Decklist Metadata information

  // Getting Drafter username
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  String? username = prefs.getString("username");
  String usernameString = username != null ? "Drafter: $username" : "";

  // Fetching the deck's cube or set name
  List<Set> allSets = await deckStorage.getAllSets();
  List<Cube> allCubes = await deckStorage.getAllCubes();
  Set? set = allSets.firstWhereOrNull((set) => set.code == deck.setId);
  Cube? cube = allCubes.firstWhereOrNull((cube) => cube.cubecobraId == deck.cubecobraId);

  String setCubeString = "";
  if (set != null) {
    setCubeString = "Set: ${set.name}";
  } else if (cube != null) {
    setCubeString = "Cube: ${cube.name}";
  }

  // Combining all the metadata and adding it to image
  String metaString = usernameString;
  metaString += deck.winLoss != null ? "\nRecord: ${deck.winLoss}" : "";
  metaString += "\n$setCubeString";

  deckImage = drawString(
    deckImage,
    metaString,
    font: regularFont,
    x: 950 +30,
    y: 350,
    color: ColorRgb8(0, 0, 0),
  );

  // Draw QR Code for Cube here (if it's a cube)
  int edgePadding = 100;
  int qrHeight = (pageHeaderMargin - 2 * edgePadding);

  Image madeByImage = await decodeAsset("assets/decklist_sharing/madeby_2.png");

  deckImage = compositeImage(deckImage, madeByImage,
    dstX: imageWidth - 2 * qrHeight - edgePadding + 70,
    dstY: edgePadding + 130,
    dstW: 2 * qrHeight,
    dstH: qrHeight,
  );

  final int maxStackCreatures = creatures.values
      .map((val) => val.length)
      .reduce((a, b) => max(a,b));
  final int maxStackNonCreatures = nonCreatures.values
      .map((val) => val.length)
      .reduce((a, b) => max(a,b));

  // Creature Curve
  int row = 0;
  int j = 0;
  for (final val in creatures.values) {
    j = 0;
    for (final card in val) {
      deckImage = drawCard(deckImage, card, row, j, yOffset: 0);
      j++;
    }
    row++;
  }

  // NonCreature Curve
  row = 0;
  j = 0;
  for (final val in nonCreatures.values) {
    j = 0;
    for (final card in val) {
      deckImage = drawCard(deckImage, card, row, j, yOffset: cardHeight + maxStackCreatures * cardStackOffset);
      j++;
    }
    row++;
  }

  // NonBasic Lands
  j = 0;
  int landsOffsetY = 2 * cardHeight + (maxStackCreatures + maxStackNonCreatures) * cardStackOffset;
  for (final card in nonBasicLands) {
    deckImage = drawCard(deckImage, card, 0, 0, yOffset: landsOffsetY, xOffset: j * (cardStackOffset * 1.5).floor());
    j++;
  }

  // Basic Lands
  final basicCounts = basics.groupFoldBy((el) => el, (int? previous, element) => (previous ?? 0) + 1);
  List<Image> diceList = await loadDice();

  j = 0;
  int numBasics = basicCounts.length;
  int initialOffsetX = imageWidth - edgePadding - cardWidth - (numBasics - 1) * (cardWidth ~/ 2);
  for (Card card in basicCounts.keys) {
    int count = basicCounts[card]!;
    debugPrint(count.toString());
    // Calculate dice needed for land count
    List<int> dice = [];
    int remainder = count;
    while (dice.sum < count) {
      if (remainder > 6) {
        dice.add(6);
        remainder -= 6;
      } else {
        dice.add(remainder);
      }
    }
    debugPrint(dice.toString());
    Image image = await getCardImage(card);
    drawCard(deckImage, image, 0, 0, yOffset: landsOffsetY, xOffset: initialOffsetX + (cardWidth ~/ 2) * j);
    // Drawing Dice
    for (int i = 0; i < dice.length; i++) {

      int diceOffsetX = initialOffsetX + (cardWidth ~/ 2) * j + cardWidth ~/ 5;
      if (j == basicCounts.length - 1) {
        diceOffsetX = initialOffsetX + (cardWidth ~/ 2) * j + cardWidth ~/ 2.4;
      }

      deckImage = compositeImage(deckImage, diceList[dice[i] - 1],
        dstX: diceOffsetX,
        dstY: pageHeaderMargin + landsOffsetY + cardHeight ~/ 3 + i * cardWidth ~/ 2.5,
        dstH: cardWidth ~/ 3,
        dstW: cardWidth ~/ 3,
      );
    }
    j++;
  }

  deckImage = copyCrop(deckImage, x: 0, y: 0, width: deckImage.width,
      height: pageHeaderMargin + landsOffsetY + cardHeight + 150
  );

  return deckImage;
}

Image drawCard(Image src, Image card, int row, int k, {int yOffset = 0, int xOffset = 0}) {
  Image croppedCard = copyCrop(card,
      x: 0,
      y: 0,
      width: card.width,
      height: card.height,
      radius: card.height / 27);

  return compositeImage(
    src,
    croppedCard,
    dstX: pageMargin + (cardWidth + cardMargin) * row + xOffset,
    dstY: pageHeaderMargin + 100 + cardStackOffset * k + yOffset,
    dstH: cardHeight,
    dstW: cardWidth,
  );
}

Future<Image> getCardImage(Card card) async {
    return getImageFromUri(card.imageUri!);
}

Future<Image> getImageFromUri(String uri) async {
  Uint8List imageBytes = (await NetworkAssetBundle(Uri.parse(uri))
      .load(uri))
      .buffer
      .asUint8List();

  Image img = decodeJpg(imageBytes)!;

  return img.convert(format: img.format, numChannels: 4);
}

Future<List<Object>> getManaCurveImages(List<Card> cards) async {

  // Initiate empty mana curves
  Map<String, List<Image>> creatures = {
    "0-1": [],
    "2": [],
    "3": [],
    "4": [],
    "5": [],
    "6+": []
  };
  Map<String, List<Image>> noncreatureSpells = {
    "0-1": [],
    "2": [],
    "3": [],
    "4": [],
    "5": [],
    "6+": []
  };
  List<Image> nonBasicLands = [];

  String? key;
  for (Card card in cards) {
    if (card.isCreature()) {
      if (card.manaValue > 5) {
        key = "6+";
      } else if (card.manaValue < 2) {
        key = "0-1";
      } else {
        key = card.manaValue.toString();
      }
      creatures[key]!.add(await getCardImage(card));
    } else if (card.isNoncreatureSpell()) {
      if (card.manaValue > 5) {
        key = "6+";
      } else if (card.manaValue < 2) {
        key = "0-1";
      } else {
        key = card.manaValue.toString();
      }
      noncreatureSpells[key]!.add(await getCardImage(card));
    } else if (card.isNonBasicLand()) {
      nonBasicLands.add(await getCardImage(card));
    }
  }

  return [
    creatures,
    noncreatureSpells,
    nonBasicLands
  ];
}

Future<List<Image>> loadDice() async {

  List<Image> diceImages = await Future.wait([1, 2, 3, 4, 5, 6]
      .map((el) => decodeAsset("assets/app_icons/dice/dice$el.png")));

  return diceImages;
}

Future<Image> decodeAsset(String path) async {
  final data = await rootBundle.load(path);

  // Utilize flutter's built-in decoder to decode asset images as it will be
  // faster than the dart decoder.
  final buffer = await ui.ImmutableBuffer.fromUint8List(
      data.buffer.asUint8List());

  final id = await ui.ImageDescriptor.encoded(buffer);
  final codec = await id.instantiateCodec(
      targetHeight: id.height,
      targetWidth: id.width);

  final fi = await codec.getNextFrame();

  final uiImage = fi.image;
  final uiBytes = await uiImage.toByteData();

  final image = Image.fromBytes(width: id.width, height: id.height,
      bytes: uiBytes!.buffer, numChannels: 4);

  return image;
}
