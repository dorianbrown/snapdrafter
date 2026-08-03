import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;

import '/data/models/card.dart';
import '/data/models/deck_upsert.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/card_repository.dart';
import '/utils/deck_text_parser.dart';
import '/utils/dropdown_position.dart';

class DeckTextEditor extends StatefulWidget {
  final String? initialText;
  final DeckRepository deckRepository;
  final CardRepository cardRepository;
  final Function(List<Card> mainboard, List<Card> sideboard)? onSave;
  final bool isEditing;
  final int? deckId; // Only for editing

  const DeckTextEditor({
    super.key,
    this.initialText,
    required this.deckRepository,
    required this.cardRepository,
    this.onSave,
    required this.isEditing,
    this.deckId,
  });

  @override
  State<DeckTextEditor> createState() => _DeckTextEditorState();
}

class _DeckTextEditorState extends State<DeckTextEditor>
    with WidgetsBindingObserver {
  static const int _pageSize = 10;
  static const double _panelWidth = 360;
  static const double _panelMaxHeight = 320;
  static const double _itemHeight = 44;

  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _cardNames = const [];
  Set<String> _lowerCardNames = const {};
  bool _isLoading = false;

  final ValueNotifier<List<String>> _suggestions = ValueNotifier(const []);
  final ValueNotifier<int> _highlightedIndex = ValueNotifier(0);
  final ValueNotifier<Offset?> _caretBottomLeft = ValueNotifier(null);
  final ValueNotifier<double> _caretHeight = ValueNotifier(0);

  BuildContext? _fieldContext;
  OverlayState? _overlay;
  OverlayEntry? _dropdownEntry;
  EditableTextState? _editableTextState;
  ScrollableState? _editableScrollable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TextEditingController(text: widget.initialText ?? '');
    _controller.addListener(_onInputChanged);
    _focusNode.addListener(_onFocusChanged);
    _loadCardNames();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _suggestions.dispose();
    _highlightedIndex.dispose();
    _caretBottomLeft.dispose();
    _caretHeight.dispose();
    _hideDropdown();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Keyboard insets or window size changed; the dialog may have moved.
    _scheduleDropdownUpdate();
  }

  Future<void> _loadCardNames() async {
    final names = await widget.cardRepository.getAllDistinctCardNames();
    if (!mounted) return;
    setState(() {
      _cardNames = names;
      _lowerCardNames = names.map((name) => name.toLowerCase()).toSet();
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hideDropdown();
    } else {
      _scheduleDropdownUpdate();
    }
  }

  void _onInputChanged() {
    _scheduleDropdownUpdate();
  }

  void _onEditableScroll() {
    _scheduleDropdownUpdate();
  }

  void _scheduleDropdownUpdate() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateDropdown());
  }

  void _updateDropdown() {
    if (!mounted || !_focusNode.hasFocus) return;
    _ensureEditableTracked();

    final suggestions = _computeSuggestions(_controller.value);
    if (suggestions.isNotEmpty) {
      _highlightedIndex.value =
          math.min(_highlightedIndex.value, suggestions.length - 1);
    }
    _suggestions.value = suggestions;

    final renderEditable = _editableTextState?.renderEditable;
    if (suggestions.isEmpty || renderEditable == null) {
      _hideDropdown();
      return;
    }

    final offset =
        _controller.selection.baseOffset.clamp(0, _controller.text.length);
    final caretRect =
        renderEditable.getLocalRectForCaret(TextPosition(offset: offset));
    _caretHeight.value = caretRect.height;
    _caretBottomLeft.value =
        renderEditable.localToGlobal(caretRect.bottomLeft);

    _showDropdown();
  }

  // Locates the field's internal EditableText (and its Scrollable) once so the
  // caret can be tracked. The walk covers only the small field subtree.
  void _ensureEditableTracked() {
    final fieldContext = _fieldContext;
    if (_editableTextState != null ||
        fieldContext == null ||
        !fieldContext.mounted) {
      return;
    }
    _editableTextState = _findEditableTextState(fieldContext);
    if (_editableTextState != null) {
      _editableScrollable = _findScrollableState(_editableTextState!.context);
      _editableScrollable?.position.addListener(_onEditableScroll);
    }
  }

  static EditableTextState? _findEditableTextState(BuildContext context) {
    EditableTextState? result;
    void visit(Element element) {
      if (result != null) return;
      if (element.widget is EditableText) {
        result = (element as StatefulElement).state as EditableTextState?;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return result;
  }

  static ScrollableState? _findScrollableState(BuildContext context) {
    ScrollableState? result;
    void visit(Element element) {
      if (result != null) return;
      if (element.widget is Scrollable) {
        result = (element as StatefulElement).state as ScrollableState?;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return result;
  }

  // Suggestions for the card line containing the cursor. Only lines of the
  // form "N Card Name" trigger suggestions, and a line whose name is already a
  // complete card name does not.
  List<String> _computeSuggestions(TextEditingValue value) {
    final info = cardLineAt(value.text, value.selection.baseOffset);
    if (info == null || info.nameFragment.isEmpty) return const [];

    final query = info.nameFragment.toLowerCase();
    if (_lowerCardNames.contains(query)) return const [];

    final prefixMatches = <String>[];
    final substringMatches = <String>[];
    for (final name in _cardNames) {
      if (prefixMatches.length >= 8 && substringMatches.length >= 8) break;
      final lower = name.toLowerCase();
      if (lower.startsWith(query)) {
        prefixMatches.add(name);
      } else if (substringMatches.length < 8 && lower.contains(query)) {
        substringMatches.add(name);
      }
    }
    return [...prefixMatches, ...substringMatches].take(8).toList();
  }

  void _commitCardName(String selectedName) {
    final text = _controller.text;
    final offset = _controller.selection.baseOffset;
    final info = cardLineAt(text, offset);
    if (info == null) return;
    final merged = replaceCardNameInLine(text, offset, selectedName);
    _controller.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(
        offset: info.lineStart + info.countPrefix.length + selectedName.length,
      ),
    );
    _hideDropdown();
  }

  bool get _isDropdownShowing => _dropdownEntry != null;

  void _showDropdown() {
    if (_dropdownEntry != null) return;
    _overlay ??= Overlay.maybeOf(_fieldContext ?? context);
    if (_overlay == null) return;
    _dropdownEntry = OverlayEntry(builder: (context) => _buildDropdown(context));
    _overlay!.insert(_dropdownEntry!);
  }

  void _hideDropdown() {
    _dropdownEntry?.remove();
    _dropdownEntry = null;
  }

  void _highlightRelative(int delta) {
    final length = _suggestions.value.length;
    if (length == 0) return;
    _highlightedIndex.value =
        ((_highlightedIndex.value + delta) % length + length) % length;
  }

  Widget _buildDropdown(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _suggestions,
      builder: (context, suggestions, _) {
        return ValueListenableBuilder<Offset?>(
          valueListenable: _caretBottomLeft,
          builder: (context, caret, _) {
            if (caret == null) return const SizedBox.shrink();
            final mediaQuery = MediaQuery.of(context);
            final panelSize = Size(
              math.min(_panelWidth, mediaQuery.size.width - 16),
              math.min(_panelMaxHeight, suggestions.length * _itemHeight + 8),
            );
            final rect = dropdownPlacement(
              caretBottomLeft: caret,
              caretHeight: _caretHeight.value,
              screenSize: mediaQuery.size,
              keyboardInset: mediaQuery.viewInsets.bottom,
              panelSize: panelSize,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _hideDropdown,
                  ),
                ),
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _highlightedIndex,
                    builder: (context, highlighted, _) {
                      return Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(4),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) {
                            final option = suggestions[index];
                            return ListTile(
                              dense: true,
                              selected: index == highlighted,
                              title: Text(
                                option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _commitCardName(option),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper method to split text into mainboard and sideboard sections
  (String, String) _splitTextBySideboard(String text) {
    final lines = text.split('\n');
    int sideboardIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().toUpperCase() == 'SIDEBOARD') {
        sideboardIndex = i;
        break;
      }
    }

    if (sideboardIndex == -1) {
      return (text, '');
    }

    String mainboardText = lines.sublist(0, sideboardIndex).join('\n');
    String sideboardText = lines.sublist(sideboardIndex + 1).join('\n');
    return (mainboardText, sideboardText);
  }

  Future<void> _parseAndSave(BuildContext context) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final (mainboardText, sideboardText) = _splitTextBySideboard(_controller.text);
      final List<String> errors = [];
      final List<Card> mainboard = await _parseCardList(mainboardText, errors);
      final List<Card> sideboard = await _parseCardList(sideboardText, errors);

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
        await widget.deckRepository.updateDeck(DeckUpsert(
          id: widget.deckId!,
          cards: mainboard,
          sideboard: sideboard,
        ));
      } else {
        // Create new deck
        await widget.deckRepository.saveNewDeck(DeckUpsert(
          cards: mainboard,
          sideboard: sideboard,
        ));
      }

      if (widget.onSave != null) {
        widget.onSave!(mainboard, sideboard);
      }

      Navigator.of(context).pop();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<Card>> _parseCardList(String text, List<String> errors) async {
    List<Card> result = [];
    final lines = text.split('\n');
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

        final matchedCard = await widget.cardRepository.getCardByName(cardName);

        if (matchedCard == null) {
          errors.add("Card not found: '$cardName'");
          continue;
        }

        for (int i = 0; i < count; i++) {
          result.add(matchedCard);
        }
      } catch (e) {
        errors.add("Error parsing '$trimmedLine': $e");
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Deck' : 'Create Deck'),
      content: SizedBox(
        width: double.maxFinite,
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp):
                AutocompletePreviousOptionIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                AutocompleteNextOptionIntent(),
            SingleActivator(LogicalKeyboardKey.pageUp):
                AutocompletePreviousPageOptionIntent(),
            SingleActivator(LogicalKeyboardKey.pageDown):
                AutocompleteNextPageOptionIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
                AutocompleteFirstOptionIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
                AutocompleteLastOptionIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
                AutocompleteFirstOptionIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
                AutocompleteLastOptionIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              AutocompletePreviousOptionIntent:
                  _DropdownAction<AutocompletePreviousOptionIntent>(
                onInvoke: (_) => _highlightRelative(-1),
                isActive: () => _isDropdownShowing,
              ),
              AutocompleteNextOptionIntent:
                  _DropdownAction<AutocompleteNextOptionIntent>(
                onInvoke: (_) => _highlightRelative(1),
                isActive: () => _isDropdownShowing,
              ),
              AutocompleteFirstOptionIntent:
                  _DropdownAction<AutocompleteFirstOptionIntent>(
                onInvoke: (_) => _highlightedIndex.value = 0,
                isActive: () => _isDropdownShowing,
              ),
              AutocompleteLastOptionIntent:
                  _DropdownAction<AutocompleteLastOptionIntent>(
                onInvoke: (_) => _highlightedIndex.value =
                    math.max(0, _suggestions.value.length - 1),
                isActive: () => _isDropdownShowing,
              ),
              AutocompletePreviousPageOptionIntent:
                  _DropdownAction<AutocompletePreviousPageOptionIntent>(
                onInvoke: (_) => _highlightRelative(-_pageSize),
                isActive: () => _isDropdownShowing,
              ),
              AutocompleteNextPageOptionIntent:
                  _DropdownAction<AutocompleteNextPageOptionIntent>(
                onInvoke: (_) => _highlightRelative(_pageSize),
                isActive: () => _isDropdownShowing,
              ),
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (intent) {
                  if (_isDropdownShowing) {
                    _hideDropdown();
                    return null;
                  }
                  return Actions.invoke(context, intent);
                },
              ),
            },
            child: Builder(
              builder: (context) {
                _fieldContext = context;
                return TextFormField(
                  smartQuotesType: SmartQuotesType.disabled,
                  controller: _controller,
                  focusNode: _focusNode,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  minLines: null,
                  decoration: InputDecoration(
                    hintText: widget.isEditing
                        ? null
                        : "1 Mox Jet\n1 Black Lotus\nSIDEBOARD\n1 Sideboard Card",
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                  ),
                );
              },
            ),
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

// Action that consumes its shortcut only while the dropdown is showing, so
// arrow keys navigate the suggestions when open and move the text cursor
// otherwise.
class _DropdownAction<T extends Intent> extends CallbackAction<T> {
  _DropdownAction({required super.onInvoke, required this.isActive});

  final bool Function() isActive;

  @override
  bool isEnabled(covariant T intent) => isActive();

  @override
  bool consumesKey(covariant T intent) => isActive();
}
