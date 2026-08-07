import 'package:flutter/material.dart' hide Card;

import '/data/models/card.dart';
import '/utils/card_art.dart';

class CardImage extends StatelessWidget {
  const CardImage({super.key, required this.card});

  final Card card;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(CardArtPreferences.cornerRadius(card)),
        child: Image.network(CardArtPreferences.resolveCardImageUri(
            card.imageUri, card.firstPrintingImageUri)!),
      ),
    );
  }
}
