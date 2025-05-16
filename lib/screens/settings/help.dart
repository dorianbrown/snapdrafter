import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

String markdownText = """
# Overview

All your decks are shown here. By swiping left/right on a deck, you can either delete it or edit it's metadata. Clicking on a deck brings you to the deck view.

In order to tag a deck a cube, it first needs to be added in the Settings menu.

# Adding a New Deck

You can add a new deck using either: an existing photo from your phone, your camera, or from a list of cards exported from elsewhere. 

When using an image, make sure:
- The titles of the cards are visible
- Each title is large enough (needs to be 32px high for OCR to work)
- Minimize reflections from overhead lights
- Avoid blurry pictures, adding light might improve this

When working in ideal conditions, expect 95% of the cards to be detected.

# Detection Preview Screen

Here you can:
- delete cards by swiping left
- add new cards with the + button at the bottom
- look at the picture taken with the `picture` button, to see what cards are missing.

# Deck Viewer

Here you can:
- Click on a card to view the oracle text and gatherer rulings
- Sample some opening hands (hand button)
- Add basics (mountain button)
- Edit or export the deck (pencil button)
- Share/download an image of the deck to social media (share button)
""";

class HelpScreen extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Help")),
      body: Container(
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        child: Markdown(
          data: markdownText,
        )
      )
    );
  }
}