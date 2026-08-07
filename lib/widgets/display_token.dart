import 'package:flutter/material.dart';

import '/utils/card_art.dart';

class DisplayToken extends StatelessWidget {
  const DisplayToken({
    super.key,
    required this.imageUri,
    required this.cards,
    this.cornerRadius = CardArtPreferences.standardCornerRadius,
  });
  // Input variables for class
  final String imageUri;
  final List cards;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      // color: Theme.of(context).highlightColor,
      child: Container(
        margin: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(cornerRadius),
                  child: Image.network(imageUri),
                )
            ),
            SizedBox(height: 8,),
            ...cards.map((cardName) => Container(
              padding: EdgeInsets.all(2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("•  "),
                  Expanded(
                    child: Text(
                      cardName,
                      style: TextStyle(
                          fontSize: 14
                      ),
                    )
                  )
                ],
              ),
            ))
          ],
        ),
      ),
    );
  }
}