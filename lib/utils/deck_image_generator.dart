import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:image/image.dart';

import 'models.dart';

Future<Image> generateDeckImage(Deck deck) async {

  // TODO: Get card images from network, convert to img.Image
  // See here: https://stackoverflow.com/questions/53182480/how-to-get-a-flutter-uint8list-from-a-network-image
  List<Image> cardImages = await Future.wait(deck.cards.map((card) async {
    Uint8List imageBytes = (await NetworkAssetBundle(Uri.parse(card.imageUri!))
        .load(card.imageUri!))
    .buffer
    .asUint8List();

    return decodeImage(imageBytes)!;
  }));

  // Colors
  Color white = ColorFloat32.rgba(255, 255, 255, 255);
  Color black = ColorFloat32.rgba(0, 0, 0, 255);

  // Note that this assets can't be resized on the fly, required regenerating
  // zip file. So this should be done after all other measurements are final.
  final fontAsset = await rootBundle.load("assets/fonts/OpenSans-Regular.zip");
  final font = BitmapFont.fromZip(fontAsset.buffer.asUint8List());


  Image deckImage = Image(width: 2000, height: 2000);
  deckImage = fill(deckImage, color: white);

  // UI Elements (framing)
  deckImage = fillRect(deckImage,
      x1: 100,
      y1: 400,
      x2: 1900,
      y2: 405,
      color: black
  );

  // Text Elements
  deckImage = drawString(deckImage, "Test String",
    font: font,
    x: 100,
    y: 100,
    color: black,
  );

  // Layout of Cards
  const double cardAspectRatio = 2.5/3.5;
  const int cardHeight = 300;
  const int horizontalMargin = 100;
  int cardWidth = (cardAspectRatio*cardHeight).floor();

  deckImage = compositeImage(deckImage, cardImages[0],
    dstX: horizontalMargin,
    dstY: 450,
    dstH: cardHeight,
    dstW: cardWidth,
  );

  deckImage = compositeImage(deckImage, cardImages[1],
    dstX: horizontalMargin + cardWidth + 10,
    dstY: 450,
    dstH: cardHeight,
    dstW: cardWidth,
  );

  return deckImage;
}