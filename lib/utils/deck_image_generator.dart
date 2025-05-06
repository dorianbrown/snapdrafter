import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:image/image.dart';

import 'models.dart';

// Layout of Page
const imageWidth = 2000;
const imageHeight = 4000;
int pageHeaderMargin = (imageHeight / 5).floor();
const int pageMargin = 50;
const int cardMargin = 15;
const int cardStackOffset = 75;
const int stackSize = 4;
const int nCol = 4;

// Card Measurements
const double cardAspectRatio = 2.5/3.5;
int cardWidth = ((imageWidth - 2*pageMargin - (nCol - 1) * cardMargin) / nCol).floor();
int cardHeight = (cardWidth / cardAspectRatio).floor();

Future<Image> generateDeckImage(Deck deck) async {

  // Split into Creatures, Noncreature spells, and non-basic lands, sorted by
  // mana value
  final sortedCardImages = await getSortedCardImages(deck.cards);
  List<Image> creatures = sortedCardImages[0];
  List<Image> nonCreatures = sortedCardImages[1];
  List<Image> nonBasicLands = sortedCardImages[2];

  // Colors
  Color white = ColorFloat32.rgba(255, 255, 255, 255);
  Color black = ColorFloat32.rgba(0, 0, 0, 255);

  // Note that this assets can't be resized on the fly, required regenerating
  // zip file. So this should be done after all other measurements are final.
  final fontAsset = await rootBundle.load("assets/fonts/OpenSans-Regular.zip");
  final font = BitmapFont.fromZip(fontAsset.buffer.asUint8List());


  Image deckImage = Image(width: imageWidth, height: imageHeight);
  deckImage = fill(deckImage, color: white);

  // UI Elements (framing)
  deckImage = fillRect(deckImage,
      x1: 100,
      y1: pageHeaderMargin,
      x2: imageWidth - 100,
      y2: pageHeaderMargin + 5,
      color: black
  );

  // Text Elements
  deckImage = drawString(deckImage, "Test String",
    font: font,
    x: 100,
    y: 100,
    color: black,
  );

  int n = 0;
  int i = 0;
  int j = 0;
  int k = 0;
  for (Image img in creatures + nonCreatures + nonBasicLands) {
    deckImage = drawCard(deckImage, img, i, j, k);
    n++;
    k++;
    if (k == stackSize) {
      k=0;
      i++;
    }
    if (i == nCol) {
      i = 0;
      j++;
    }
  }

  return deckImage;
}

Image drawCard(Image src, Image card, int i, int j, int k) {
  return compositeImage(src, card,
      dstX: pageMargin + (cardWidth + cardMargin) * i,
      dstY: pageHeaderMargin + 50 + (cardHeight + cardMargin + stackSize * cardStackOffset) * j + cardStackOffset * k,
      dstH: cardHeight,
      dstW: cardWidth,
  );
}

Future<List<Image>> getCardImages(List<Card> cards) async {
  return Future.wait(cards.map((card) async {
    Uint8List imageBytes = (await NetworkAssetBundle(Uri.parse(card.imageUri!))
        .load(card.imageUri!))
        .buffer
        .asUint8List();

    return decodeImage(imageBytes)!;
  }));
}

Future<List<List<Image>>> getSortedCardImages(List<Card> cards) async {
  List<Card> creatures = [];
  List<Card> noncreatureSpells = [];
  List<Card> nonBasicLands = [];

  for (Card card in cards) {
    if (card.isCreature()) {
      creatures.add(card);
    } else if (card.isNoncreatureSpell()) {
      noncreatureSpells.add(card);
    } else if (card.isNonBasicLand()) {
      nonBasicLands.add(card);
    }
  }

  creatures.sort((a, b) => a.manaValue - b.manaValue);
  noncreatureSpells.sort((a, b) => a.manaValue - b.manaValue);
  nonBasicLands.sort((a, b) => a.title.compareTo(b.title));

  return [
    await getCardImages(creatures),
    await getCardImages(noncreatureSpells),
    await getCardImages(nonBasicLands)];
}