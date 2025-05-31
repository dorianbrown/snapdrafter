import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DisplayToken extends StatelessWidget {
  const DisplayToken({super.key, required this.imageUri, required this.cards});
  // Input variables for class
  final String imageUri;
  final List cards;

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
                  borderRadius: BorderRadius.circular(25),
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