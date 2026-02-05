import 'package:flutter/material.dart' hide Card;
import 'package:collection/collection.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '/data/models/card.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/card_repository.dart';

class DeckTextEditor extends StatefulWidget {
  final String? initialText;
  final DeckRepository deckRepository;
  final CardRepository cardRepository;
  final Function(List<Card>)? onSave;
  final bool isEditing;
  final int? deckId; // Only for editing

  const DeckTextEditor({
    super.key,
    this.initialText,
    required this.deckRepository,
    required this.cardRepository,
    this.onSave,
    this.isEditing = false,
    this.deckId,
  });

  @override
  State<DeckTextEditor> createState() => _DeckTextEditorState();
}

class _DeckTextEditorState extends State<DeckTextEditor> {
  late TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parseAndSave(BuildContext context) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      final allCards = await widget.cardRepository.getAllCards();
      final List<Card> deckList = [];
      final List<String> errors = [];
      
      final lines = _controller.text.split('\n');
      final regex = RegExp(r'^(\d+)\s(.+)$');
      
      for (String line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        final regexMatch = regex.allMatches(trimmedLine);
        if (regexMatch.isEmpty) {
          errors.add("Incorrect format for '$trimmedLine'");
          continue;
        }
        
        try {
          final count = int.parse(regexMatch.first[1]!);
          final cardName = regexMatch.first[2]!;
          
          final Card? matchedCard = allCards.firstWhereOrNull((card) {
            if (card.name.contains(" // ")) {
              return card.name.split(" // ").any(
                (name) => name.toLowerCase() == cardName.toLowerCase()
              );
            }
            return card.name.toLowerCase() == cardName.toLowerCase();
          });
          
          if (matchedCard == null) {
            errors.add("Card not found: '$cardName'");
            continue;
          }
          
          for (int i = 0; i < count; i++) {
            deckList.add(matchedCard);
          }
        } catch (e) {
          errors.add("Error parsing '$trimmedLine': $e");
        }
      }
      
      if (errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errors.join('\n')),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      
      if (widget.isEditing && widget.deckId != null) {
        // Update existing deck
        await widget.deckRepository.updateDecklist(widget.deckId!, deckList);
      } else {
        // Create new deck
        await widget.deckRepository.saveNewDeck(DateTime.now(), deckList);
      }
      
      if (widget.onSave != null) {
        widget.onSave!(deckList);
      }
      
      Navigator.of(context).pop();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Deck' : 'Create Deck'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextFormField(
          controller: _controller,
          expands: true,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: null,
          decoration: InputDecoration(
            hintText: widget.isEditing 
              ? null 
              : "1 Mox Jet\n1 Black Lotus\n1 ...",
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      ),
      actions: [
        if (widget.isEditing)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _controller.text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy All'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Discard'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : () => _parseAndSave(context),
          child: _isLoading 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
        ),
      ],
    );
  }
}
