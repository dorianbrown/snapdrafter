import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:fl_chart/fl_chart.dart';
import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:loader_overlay/loader_overlay.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:snapdrafter/data/repositories/card_repository.dart';
import 'package:url_launcher/url_launcher.dart';

import '/utils/deck_image_generator.dart';
import '/widgets/card_image.dart';
import '/widgets/deck_text_editor.dart';
import '/widgets/deck_edit_dialog.dart';
import '/widgets/display_token.dart';
import '/data/repositories/token_repository.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/set_repository.dart';
import '/data/repositories/cube_repository.dart';
import '/data/models/card.dart';
import '/data/models/deck.dart';
import '/data/models/deck_upsert.dart';
import '/data/models/set.dart' as set_model;
import '/data/models/cube.dart';
import '/utils/constants.dart';
import '/utils/deck_change_notifier.dart';
import '/utils/basic_land_calculator.dart';

const _headerStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline,
);

const _sideboardHeaderStyle = TextStyle(
  fontSize: 24, // Larger than the regular header
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.underline,
);

class DeckViewer extends StatefulWidget {
  final Deck deck;
  final Future<String?>? pendingImageFuture;
  const DeckViewer({super.key, required this.deck, this.pendingImageFuture});

  @override
  DeckViewerState createState() => DeckViewerState(deck);
}

class DeckViewerState extends State<DeckViewer> {
  Deck deck;
  DeckViewerState(this.deck);

  final DeckChangeNotifier _notifier = DeckChangeNotifier();
  late CardRepository cardRepository;
  late TokenRepository tokenRepository;
  late DeckRepository deckRepository;
  Map groupedTokens = {};
  List<set_model.Set> _sets = [];
  List<Cube> _cubes = [];
  List<String> _allTags = [];
  bool _dataLoaded = false;
  int columnCount = 3;
  bool _manacurveSplitByColor = false;
  final Set<String> _disabledSeries = {};
  bool _imageIsLoading = false;
  String? _loadedImagePath;

  @override
  void initState() {
    super.initState();
    _loadedImagePath = deck.imagePath;
    if (widget.pendingImageFuture != null) {
      _imageIsLoading = true;
      widget.pendingImageFuture!.then((path) {
        if (mounted) {
          setState(() {
            _loadedImagePath = path;
            _imageIsLoading = false;
          });
        }
      });
    }
    _loadCards();
    tokenRepository = TokenRepository();
    deckRepository = DeckRepository();
    _loadSetsAndCubesAndTags();
    tokenRepository.getDeckTokens(deck.id).then((val) {
      setState(() {
        groupedTokens = val;
      });
    });
  }

  String get _setCubeLabel {
    if (deck.cubecobraId != null && _cubes.isNotEmpty) {
      try {
        return _cubes.firstWhere((c) => c.cubecobraId == deck.cubecobraId).name;
      } catch (_) {}
    }
    if (deck.setId != null && _sets.isNotEmpty) {
      try {
        return _sets.firstWhere((s) => s.code == deck.setId).code.toUpperCase();
      } catch (_) {}
    }
    return "—";
  }

  Widget _buildMetadataChip(String label, {IconData? icon}) {
    final chipColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: BoxConstraints(maxWidth: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 0.5,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: chipColor),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                color: chipColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCards() async {
    cardRepository = CardRepository();
  }

  Future<void> _loadSetsAndCubesAndTags() async {
    final results = await Future.wait([
      SetRepository().getAllSets(),
      CubeRepository().getAllCubes(),
      deckRepository.getAllTags(),
    ]);
    setState(() {
      _sets = results[0] as List<set_model.Set>;
      _cubes = results[1] as List<Cube>;
      _allTags = results[2] as List<String>;
      _dataLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LoaderOverlay(
      overlayWidgetBuilder: (_) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepPurpleAccent),
              SizedBox(height: 50),
              Text(
                "Creating Decklist Image...",
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
        );
      },
      overlayColor: Colors.black38.withAlpha(200),
      child: Scaffold(
        appBar: AppBar(
          title: deck.name != null && deck.name!.isNotEmpty
              ? Text(deck.name!, overflow: TextOverflow.ellipsis)
              : null,
          actionsPadding: EdgeInsets.fromLTRB(0, 0, 10, 0),
          actions: [
            Row(
              children: [
                PopupMenuButton<int>(
                  initialValue: columnCount,
                  tooltip: "Display columns",
                  onSelected: (value) => setState(() => columnCount = value),
                  child: IconButton(
                    icon: Icon(switch (columnCount) {
                      2 => Icons.looks_two,
                      3 => Icons.looks_3,
                      4 => Icons.looks_4,
                      _ => Icons.looks_3,
                    }),
                    onPressed: null,
                  ),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 2,
                      checked: columnCount == 2,
                      child: const Icon(Icons.looks_two),
                    ),
                    CheckedPopupMenuItem(
                      value: 3,
                      checked: columnCount == 3,
                      child: const Icon(Icons.looks_3),
                    ),
                    CheckedPopupMenuItem(
                      value: 4,
                      checked: columnCount == 4,
                      child: const Icon(Icons.looks_4),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: "Edit Deck Info",
                  icon: Icon(Icons.edit),
                  onPressed: _dataLoaded
                      ? () => showDeckEditDialog(
                          context,
                          deck: deck,
                          sets: _sets,
                          cubes: _cubes,
                          allTags: _allTags,
                          deckRepository: deckRepository,
                          onSaved: () async {
                            _notifier.markNeedsRefresh();
                            final decks = await deckRepository.getAllDecks();
                            final updated = decks.firstWhere(
                              (d) => d.id == deck.id,
                            );
                            setState(() => deck = updated);
                          },
                        )
                      : null,
                ),
                IconButton(
                  tooltip: "Delete Deck",
                  icon: Icon(Icons.delete),
                  onPressed: _confirmDeleteViewerDeck,
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(25, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (deck.wins != null) ...[
                        _buildMetadataChip(
                          "${deck.wins ?? 0}-${deck.losses ?? 0}${deck.draws != 0 ? '-${deck.draws}' : ''}",
                          icon: Icons.emoji_events
                        ),
                      ],
                      if (_setCubeLabel != "—") ...[
                        const SizedBox(width: 6),
                        _buildMetadataChip(
                          _setCubeLabel,
                          icon: Icons.apps,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _buildMetadataChip(deck.ymd, icon: Icons.calendar_today),
                      Spacer(),
                      Text(
                        "${deck.cards.length} cards",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          alignment: Alignment.topCenter,
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              generateManaCurve(deck.cards),
              SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text("Type", style: TextStyle(fontSize: 11),)),
                    ButtonSegment(value: true, label: Text("Color", style: TextStyle(fontSize: 11),)),
                  ],
                  selected: {_manacurveSplitByColor},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _manacurveSplitByColor = newSelection.first;
                      _disabledSeries.clear();
                    });
                  },
                ),
              ),
              ...generateDeckView(deck, columnCount),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 65,
          child: Row(
            children: [
              IconButton(
                tooltip: "Sample Starting Hand",
                icon: Icon(Icons.back_hand),
                onPressed: () => showRandomHand(deck),
              ),
              IconButton(
                tooltip: "Add basics",
                icon: Icon(Icons.landscape),
                onPressed: () => showBasicsEditor(deck),
              ),
              IconButton(
                tooltip: "Show Deck Tokens",
                icon: Icon(Icons.cruelty_free),
                onPressed: groupedTokens.isNotEmpty
                    ? () => showDeckTokens(deck.id)
                    : null,
              ),
              Spacer(),
              // TODO: Broken currently
              // IconButton(
              //   tooltip: "Share to CubeCobra",
              //   icon: SvgPicture.asset(
              //     "assets/app_icons/monochrome_cubecobra.svg",
              //     height: 28,
              //     colorFilter: ColorFilter.mode(
              //         // Theme.of(context).iconTheme.color!,
              //         Theme.of(context).unselectedWidgetColor,
              //         BlendMode.srcIn),
              //   ),
              //   onPressed: () => shareWithCubeCobra(deck),
              // ),
              IconButton(
                tooltip: "Edit Decklist",
                icon: Icon(Icons.format_list_numbered),
                onPressed: () => showDeckEditor(deck),
              ),
              IconButton(
                tooltip: "View Deck Photo",
                icon: Icon(Icons.image),
                onPressed: _loadedImagePath != null
                    ? () =>
                        createInteractiveImageViewer(_loadedImagePath!, context)
                    : null,
              ),
              IconButton(
                tooltip: "Share",
                icon: Icon(Icons.share),
                onPressed: () async {
                  context.loaderOverlay.show();
                  await shareDeck(deck);
                  context.loaderOverlay.hide();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteViewerDeck() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmation'),
        content: const Text('Are you sure you want to delete this deck?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await deckRepository.deleteDeck(deck.id);
              Navigator.of(dialogContext).pop();
              _notifier.markNeedsRefresh();
              Navigator.of(context).pop();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future showDeckTokens(int deckId) async {
    // Create Dialog window to display tokens and associated cards
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          // title: Text("Tokens"),
          insetPadding: EdgeInsets.all(30),
          contentPadding: EdgeInsets.all(10),
          content: Container(
            width: double.maxFinite,
            child: MasonryGridView.count(
              itemCount: groupedTokens.keys.length,
              shrinkWrap: true,
              crossAxisCount: 2,
              itemBuilder: (context, index) => DisplayToken(
                imageUri: groupedTokens.keys.toList()[index],
                cards: groupedTokens.values.toList()[index]["cards"],
                cornerRadius: groupedTokens.values.toList()[index]["corner_radius"],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Back"),
            ),
          ],
        );
      },
    );
  }

  Future shareDeck(Deck deck) async {
    final ui.Image image = await generateDeckImage(deck);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final imageBytes = byteData!.buffer.asUint8List();
    image.dispose();

    final params = ShareParams(
      files: [XFile.fromData(imageBytes, mimeType: 'image/png')],
    );

    SharePlus.instance.share(params);
  }

  Future showBasicsEditor(Deck deck) async {
    final basicLands = await cardRepository.getBasicLands();
    final plains = basicLands.firstWhere((c) => c.name == 'Plains');
    final island = basicLands.firstWhere((c) => c.name == 'Island');
    final swamp = basicLands.firstWhere((c) => c.name == 'Swamp');
    final mountain = basicLands.firstWhere((c) => c.name == 'Mountain');
    final forest = basicLands.firstWhere((c) => c.name == 'Forest');

    Map<String, int> basicCounts = {
      'Plains': deck.cards.where((c) => c.name == 'Plains').length,
      'Island': deck.cards.where((c) => c.name == 'Island').length,
      'Swamp': deck.cards.where((c) => c.name == 'Swamp').length,
      'Mountain': deck.cards.where((c) => c.name == 'Mountain').length,
      'Forest': deck.cards.where((c) => c.name == 'Forest').length,
    };

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool calculating = false;
        BasicLandResult? _result;

        const _mutedStyle = TextStyle(fontSize: 12, color: Colors.grey);
        const _boldStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
        const _subStyle = TextStyle(fontSize: 14);
        const _colorToChar = {
          'White': 'W', 'Blue': 'U', 'Black': 'B',
          'Red': 'R', 'Green': 'G',
        };
        const _plainsToColor = {
          'Plains': 'White', 'Island': 'Blue', 'Swamp': 'Black',
          'Mountain': 'Red', 'Forest': 'Green',
        };

        WidgetSpan _manaIcon(String char, {double height = 14}) {
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SvgPicture.asset('assets/svg_icons/$char.svg', height: height),
          );
        }

        Widget? _pipLabel(String landName, BasicLandResult r) {
          final colorName = _plainsToColor[landName];
          if (colorName == null) return null;
          final pips = r.weightedPips[colorName];
          if (pips == null || pips == 0) return null;
          return Text.rich(
            textAlign: TextAlign.left,
            TextSpan(
              style: _mutedStyle,
              children: [
                _manaIcon(_colorToChar[colorName]!, height: 12),
                TextSpan(text: '  ${pips.toStringAsFixed(1)}'),
              ],
            ),
          );
        }

        Widget _buildSummary(BasicLandResult r) {
          final perColor = <String, int>{};
          for (final s in r.nonBasicLandSources) {
            for (final c in s.colors) {
              perColor[c] = (perColor[c] ?? 0) + 1;
            }
          }
          final colorEntries = perColor.entries.toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text('Total lands: ', style: _boldStyle),
                Text('${r.totalLands}', style: _subStyle),
                if (r.rampCount > 0) ...[
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                        '(17 − ${r.rampCount ~/ 2} from ${r.rampCount} ramp)',
                        style: _mutedStyle),
                  ),
                ],
              ]),
              SizedBox(height: 4),
              Row(children: [
                Text('Basic slots: ', style: _boldStyle),
                Text('${r.basicLandSlots}', style: _subStyle),
                if (r.nonBasicLandCount > 0) ...[
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                        '(${r.totalLands} total − ${r.nonBasicLandCount} non-basic)',
                        style: _mutedStyle),
                  ),
                ],
              ]),
              if (r.nonBasicLandSources.isNotEmpty) ...[
                SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Non-basic sources: ',
                          style: _boldStyle),
                      for (int i = 0;
                          i < colorEntries.length;
                          i++) ...[
                        _manaIcon(
                            _colorToChar[colorEntries[i].key]!),
                        TextSpan(
                            text: ' ${colorEntries[i].value}',
                            style: _subStyle),
                        if (i < colorEntries.length - 1)
                          TextSpan(
                              text: '  ', style: _subStyle),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        }

        Widget _buildFixingCards(BasicLandResult r) {
          final hasTotals = r.virtualFixing.values.any((v) => v > 0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              if (hasTotals)
                Wrap(spacing: 8, children: [
                  Text('Fixing sources:', style: _boldStyle),
                  ...r.virtualFixing.entries
                      .where((e) => e.value > 0)
                      .map((e) => Text.rich(TextSpan(
                        style: _subStyle,
                        children: [
                          _manaIcon(_colorToChar[e.key]!),
                          TextSpan(
                              text: ' ${e.value.toStringAsFixed(2)}'),
                        ],
                      ))),
                ]),
              if (r.fixingCards.isNotEmpty) ...[
                SizedBox(height: 4),
                ...r.fixingCards.map((fc) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '+${fc.weight.toStringAsFixed(2)} (${fixingTagLabel(fc.tag)}): ${fc.name}',
                    style: _mutedStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
              ],
            ],
          );
        }

        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: Text('Edit Basic Lands'),
              content: Stack(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(builderContext).size.height *
                            0.6),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                Text.rich(
                  TextSpan(
                    style: _subStyle,
                    children: [
                      TextSpan(text: 'Deck colors: '),
                      for (int i = 0; i < deck.colors.length; i++) ...[
                        if (i > 0)
                          const WidgetSpan(child: SizedBox(width: 4)),
                        _manaIcon(deck.colors[i], height: 14),
                      ],
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                          SizedBox(height: 12),
                          if (_result != null) ...[
                            _buildSummary(_result!),
                            if (_result!.fixingCards.isNotEmpty ||
                                _result!.virtualFixing.values
                                    .any((v) => v > 0))
                              _buildFixingCards(_result!),
                            SizedBox(height: 15),
                            Divider(height: 1),
                          ],
                          SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  'Plains',
                                  'Island',
                                  'Swamp',
                                  'Mountain',
                                  'Forest',
                                ]
                                    .map((name) => SizedBox(
                                          height: 32,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child:
                                                Text(name, style: _subStyle),
                                          ),
                                        ))
                                    .toList(),
                              ),
                              if (_result != null) ...[
                                SizedBox(
                                  width: 28,
                                ),
                                Padding(
                                    padding:
                                        EdgeInsetsGeometry.only(top: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        'Plains',
                                        'Island',
                                        'Swamp',
                                        'Mountain',
                                        'Forest',
                                      ].map((name) => SizedBox(
                                            height: 32,
                                            child:
                                                _pipLabel(name, _result!),
                                          )).toList(),
                                    )),
                              ],
                              SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  'Plains',
                                  'Island',
                                  'Swamp',
                                  'Mountain',
                                  'Forest',
                                ].map((name) {
                                  return SizedBox(
                                    height: 32,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            iconSize: 18,
                                            constraints: BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(Icons.remove),
                                            onPressed: () {
                                              setDialogState(() {
                                                if (basicCounts[name]! > 0) {
                                                  basicCounts[name] =
                                                      basicCounts[name]! -
                                                          1;
                                                }
                                              });
                                            },
                                          ),
                                          Text('${basicCounts[name]}',
                                              style: _subStyle),
                                          IconButton(
                                            iconSize: 18,
                                            constraints: BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24),
                                            padding: EdgeInsets.zero,
                                            icon: Icon(Icons.add),
                                            onPressed: () {
                                              setDialogState(() {
                                                basicCounts[name] =
                                                    basicCounts[name]! +
                                                        1;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (calculating)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Calculate'),
                  onPressed: () async {
                    setDialogState(() => calculating = true);
                    try {
                      final result = await calculateBasicLands(deck);
                      setDialogState(() {
                        _result = result;
                        for (final name in [
                          'Plains',
                          'Island',
                          'Swamp',
                          'Mountain',
                          'Forest',
                        ]) {
                          basicCounts[name] = 0;
                        }
                        const colorToPlains = <String, String>{
                          'White': 'Plains',
                          'Blue': 'Island',
                          'Black': 'Swamp',
                          'Red': 'Mountain',
                          'Green': 'Forest',
                        };
                        for (final entry in result.basics.entries) {
                          final plainsName = colorToPlains[entry.key];
                          if (plainsName != null) {
                            basicCounts[plainsName] = entry.value;
                          }
                        }
                      });
                    } finally {
                      setDialogState(() => calculating = false);
                    }
                  },
                ),
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text('Save'),
                  onPressed: () async {
                    // Update deck with new basic land counts
                    List<Card> newCards = deck.cards
                        .where(
                          (c) => ![
                            'Plains',
                            'Island',
                            'Swamp',
                            'Mountain',
                            'Forest',
                          ].contains(c.name),
                        )
                        .toList();

                    // Add new basic lands
                    for (var entry in basicCounts.entries) {
                      Card basicLand;
                      switch (entry.key) {
                        case 'Plains':
                          basicLand = plains;
                          break;
                        case 'Island':
                          basicLand = island;
                          break;
                        case 'Swamp':
                          basicLand = swamp;
                          break;
                        case 'Mountain':
                          basicLand = mountain;
                          break;
                        case 'Forest':
                          basicLand = forest;
                          break;
                        default:
                          continue;
                      }
                      newCards.addAll(List.filled(entry.value, basicLand));
                    }

                    // Update both local deck state and database
                    setState(() {
                      deck.cards = newCards;
                      _notifier.markNeedsRefresh();
                    });
                    // Force refresh the FutureBuilder by creating a new future
                    deckRepository
                        .updateDeck(
                          DeckUpsert(
                            id: deck.id,
                            cards: newCards,
                            sideboard: deck
                                .sideboard, // Make sure to preserve sideboard
                          ),
                        )
                        .then((_) {
                          Navigator.of(context).pop();
                        });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showRandomHand(Deck deck) {
    List<Card> hand = [];
    List<Card> remainingCards = [];

    void drawNewHand() {
      hand = deck.cards.sample(7);
      remainingCards = List.from(deck.cards); // Make copy
      for (var card in hand) {
        remainingCards.remove(card);
      }
      remainingCards.shuffle();
    }

    void drawCard() {
      if (remainingCards.isEmpty) {
        drawNewHand();
      } else {
        hand.add(remainingCards.removeAt(0));
      }
    }

    drawNewHand();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Sample Starting Hand"),
              insetPadding: EdgeInsets.all(15),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * .9,
                child: GridView.count(
                  childAspectRatio: 0.72,
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  children: hand.map((card) => CardImage(card: card)).toList(),
                ),
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Back"),
                ),
                TextButton(
                  onPressed: () {
                    drawCard();
                    setState(() {});
                  },
                  child: const Text("Draw Card"),
                ),
                TextButton(
                  onPressed: () {
                    drawNewHand();
                    setState(() {});
                  },
                  child: const Text("New Hand"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showDeckEditor(Deck deck) {
    showDialog(
      context: context,
      builder: (context) => DeckTextEditor(
        initialText: deck.generateTextExport(),
        deckRepository: deckRepository,
        cardRepository: cardRepository,
        isEditing: true,
        deckId: deck.id,
        onSave: (newMainboard, newSideboard) {
          setState(() {
            deck.cards = newMainboard;
            deck.sideboard = newSideboard;
            _notifier.markNeedsRefresh();
          });
          deckRepository.updateDeck(
            DeckUpsert(
              id: deck.id,
              cards: newMainboard,
              sideboard: newSideboard,
            ),
          );
        },
      ),
    );
  }

  Widget generateManaCurve(List<Card> cards) {
    final manaValues = [0, 1, 2, 3, 4, 5, 6, 7];
    final manaLabels = ["0", "1", "2", "3", "4", "5", "6", "7+"];

    bool Function(Card) manaCondition(int val) {
      return (card) => val < 7 ? card.manaValue == val : card.manaValue > 6;
    }

    final labelToColor =
        _manacurveSplitByColor ? _colorChartColors : _typeChartColors;
    final labelOrder =
        _manacurveSplitByColor ? colorOrder : _typeLabels;
    final String Function(Card) labelKeyFn = _manacurveSplitByColor
        ? (c) => c.color()
        : (c) => c.type == "Creature" ? "Creature" : "Non-Creature";

    final labelTotals = {for (final label in labelOrder) label: 0};
    for (final label in labelOrder) {
      labelTotals[label] = cards
          .where((c) => c.type != "Land")
          .where((c) => labelKeyFn(c) == label)
          .length;
    }

    final legendItems = labelOrder
        .where((label) => labelTotals[label]! > 0)
        .map((label) {
          final isDisabled = _disabledSeries.contains(label);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isDisabled) {
                  _disabledSeries.remove(label);
                } else {
                  _disabledSeries.add(label);
                }
              });
            },
            child: Opacity(
              opacity: isDisabled ? 0.3 : 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: labelToColor[label] ?? Colors.grey,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      decoration:
                          isDisabled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        })
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth =
                  constraints.maxWidth / (manaLabels.length * 1.6);
              final groupsSpace = barWidth / 4;

              final barGroups = manaValues.asMap().entries.map((entry) {
                final x = entry.key;
                final val = entry.value;
                final condition = manaCondition(val);

                final stacks = <BarChartRodStackItem>[];
                double runningY = 0;

                for (final label in labelOrder) {
                  if (_disabledSeries.contains(label)) continue;
                  final count = cards
                      .where(condition)
                      .where((c) => c.type != "Land")
                      .where((c) => labelKeyFn(c) == label)
                      .length;
                  if (count > 0) {
                    stacks.add(BarChartRodStackItem(
                      runningY,
                      runningY + count,
                      labelToColor[label] ?? Colors.grey,
                    ));
                    runningY += count;
                  }
                }

                return BarChartGroupData(
                  x: x,
                  barRods: [
                    BarChartRodData(
                      toY: runningY,
                      rodStackItems: stacks,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                      width: barWidth,
                    ),
                  ],
                );
              }).toList();

              return BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= manaLabels.length) {
                            return Container();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              manaLabels[idx],
                              style: TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 2,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max) return Container();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              meta.formattedValue,
                              style: TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 2,
                    checkToShowHorizontalLine: (value) => value % 1 == 0,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withAlpha(30),
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  groupsSpace: groupsSpace,
                  barGroups: barGroups,
                ),
              );
            },
          ),
        ),
        if (legendItems.isNotEmpty) ...[
          SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: legendItems,
          ),
        ],
      ],
    );
  }

  static const _typeLabels = ["Creature", "Non-Creature"];

  static const _typeChartColors = {
    "Creature": Color(0xFF2F68C3),
    "Non-Creature": Color(0xFF7DB6DF),
  };

  static const _colorChartColors = {
    "White": Color(0xFFDAD1B8),
    "Blue": Color(0xFF0A7ACA),
    "Black": Color(0xFF3A3939),
    "Red": Color(0xFFA8333B),
    "Green": Color(0xFF297E31),
    "Multicolor": Color(0xFFD1A84E),
    "Colorless": Color(0xFF979393),
  };

  // static const _colorChartColors = {
  //   "White": Color.fromRGBO(249, 250, 244, 1),
  //   "Blue": Color.fromRGBO(14, 104, 171, 1),
  //   "Black": Color(0xFF323030),
  //   "Red": Color(0xFFA12931),
  //   "Green": Color(0xFF127024),
  //   "Multicolor": Color(0xFFC88D0E),
  //   "Colorless": Color(0xFF858484),
  // };

  List<Widget> generateDeckView(Deck deck, int columnCount) {
    final List<Widget> deckView = [];

    getAttribute(card) => card.type;
    final uniqueGroupings = typeOrder;

    for (String attribute in uniqueGroupings) {
      deck.cards.sort((a, b) => a.manaValue.compareTo(b.manaValue));
      List<Widget> cardWidgets = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries
          .map((entry) => createVisualCardPopup(entry.key, entry.value))
          .toList();

      int numCards = deck.cards
          .where((card) => getAttribute(card) == attribute)
          .length;

      List<Widget> header = [
        Container(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
          child: Text("$attribute ($numCards)", style: _headerStyle),
        ),
      ];

      if (cardWidgets.isNotEmpty) {
        deckView.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...header,
              GridView.count(
                physics: NeverScrollableScrollPhysics(),
                childAspectRatio: 0.72,
                crossAxisCount: columnCount,
                shrinkWrap: true,
                children: cardWidgets,
              ),
            ],
          ),
        );
      }
    }

    if (deck.sideboard.isNotEmpty) {
      deckView.add(
        Container(
          padding: const EdgeInsets.fromLTRB(0, 30, 0, 10),
          child: Text(
            "Sideboard (${deck.sideboard.length})",
            style: _sideboardHeaderStyle,
          ),
        ),
      );

      deck.sideboard.sort((a, b) => a.manaValue.compareTo(b.manaValue));

      List<Widget> sideboardWidgets = deck.sideboard
          .groupFoldBy((item) => item, (int? sum, item) => (sum ?? 0) + 1)
          .entries
          .map((entry) => createVisualCardPopup(entry.key, entry.value))
          .toList();

      deckView.add(
        GridView.count(
          physics: NeverScrollableScrollPhysics(),
          childAspectRatio: 0.72,
          crossAxisCount: columnCount,
          shrinkWrap: true,
          children: sideboardWidgets,
        ),
      );
    }

    return deckView;
  }

  Widget createVisualCardPopup(Card card, int count) {
    return Container(
      padding: EdgeInsets.all(2),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text("Card Information", style: TextStyle(fontSize: 18)),
            content: CardPopup(card: card),
            actions: [
              TextButton(
                child: Text("Dismiss"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        child: Stack(
          children: [
            CardImage(card: card),
            if (count > 1)
              Container(
                alignment: Alignment.bottomLeft,
                margin: EdgeInsets.symmetric(vertical: 15, horizontal: 13),
                child: Text(
                  "${count}x",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    background: Paint()
                      ..color = Colors.black.withAlpha(180)
                      ..strokeWidth = 11
                      ..strokeJoin = StrokeJoin.round
                      ..strokeCap = StrokeCap.round
                      ..style = PaintingStyle.stroke,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void shareWithCubeCobra(Deck deck) {
  // Construct query parameters containing list of cards
  Map<String, dynamic> queryParams = {
    "o": deck.cards.map((card) => card.oracleId).toList(),
  };
  // If no sideboard, we omit the "s" key
  if (deck.sideboard.isNotEmpty) {
    queryParams["s"] = deck.sideboard.map((card) => card.oracleId).toList();
  }
  // Launch URL to CubeCobra for importing deck
  Uri cubecobraUri = Uri(
    scheme: "https",
    host: "cubecobra.com",
    path: "cube/records/import",
    queryParameters: queryParams,
  );
  launchUrl(cubecobraUri);
}

void createInteractiveImageViewer(String imagePath, BuildContext context) {
  // This is currently the best approach without knowing the images HxW
  // dimensions. Requires a background, and for
  showDialog(
    context: context,
    builder: (innerContext) {
      return AlertDialog(
        insetPadding: EdgeInsets.zero, // Maximize viewing area
        contentPadding: EdgeInsets.zero, // Maximize viewing area
        actions: [
          TextButton(
            style: ButtonStyle(
              foregroundColor: MaterialStateProperty.all(Colors.white),
              backgroundColor: MaterialStateProperty.all(Colors.black38),
            ),
            child: const Text("Share"),
            onPressed: () async {
              final params = ShareParams(files: [XFile(imagePath)]);
              await SharePlus.instance.share(params);
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            style: ButtonStyle(
              foregroundColor: MaterialStateProperty.all(Colors.white),
              backgroundColor: MaterialStateProperty.all(Colors.black38),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Back"),
          ),
        ],
        content: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                minScale: 1,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Image.file(File(imagePath)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CardPopup extends StatefulWidget {
  final Card card;
  const CardPopup({super.key, required this.card});

  @override
  State<CardPopup> createState() => _CardPopupState();
}

class _CardPopupState extends State<CardPopup> {
  late Future rulingsFuture;
  late Future cardDataFuture;

  @override
  void initState() {
    super.initState();
    rulingsFuture = getRulingsData(widget.card.scryfallId);
    cardDataFuture = getCardData(widget.card.scryfallId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 20,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          child: CardImage(card: widget.card),
        ),
        FutureBuilder(
          future: cardDataFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final Map<String, dynamic> cardData = snapshot.data!;
              return displayCardData(cardData);
            }
            return const CircularProgressIndicator();
          },
        ),
        Divider(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [Text("Rulings", style: _headerStyle)],
        ),
        FutureBuilder(
          future: rulingsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final rulings = snapshot.data!;
              return Column(
                children: [
                  for (var ruling in rulings)
                    ListTile(
                      contentPadding: EdgeInsets.all(0),
                      title: Text(ruling["published_at"]),
                      subtitle: Text(ruling["comment"]),
                    ),
                ],
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ],
    );
  }

  Future getCardData(String scryfallId) async {
    final response = await http.get(
      Uri.parse("https://api.scryfall.com/cards/$scryfallId"),
      headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'},
    );
    if (response.statusCode == 200) {
      final payload = json.decode(response.body);
      return payload;
    } else {
      throw Exception("Failed to load rulings");
    }
  }

  Future getRulingsData(String scryfallId) async {
    final response = await http.get(
      Uri.parse("https://api.scryfall.com/cards/$scryfallId/rulings"),
      headers: {'User-Agent': 'SnapDrafter/1.0', 'Accept': '*/*'},
    );
    if (response.statusCode == 200) {
      final payload = json.decode(response.body);
      final rulings = payload["data"];
      return rulings;
    } else {
      throw Exception("Failed to load rulings");
    }
  }
}

Widget displayCardData(Map<String, dynamic> cardData) {
  List<dynamic>? cardFaces = cardData["card_faces"];

  final style = TextStyle(fontStyle: FontStyle.italic);

  cardFaces ??= [cardData];

  List<Widget> widgets = [];
  for (var cardFace in cardFaces) {
    widgets += [
      Divider(height: 6),
      Text(cardFace["type_line"], style: style),
      Divider(height: 6, endIndent: 225),
      for (String text in cardFace["oracle_text"].split("\n"))
        Text(text, style: style),
    ];
  }

  return Column(
    spacing: 8,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: widgets,
  );
}
