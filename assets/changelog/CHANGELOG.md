# SnapDrafter Changelog

## 1.2.2

#### Features
- Draft mode promoted to 'experimental'
- Added autocomplete to multiline input fields
- Added a "Prefer original printing" option in settings

#### Bugfixes
- Various BLE fixes
- Fixed light mode issues
- Various fixes for preferred printing
- Lots of smaller fixes

#### Other

- Big migration to oracle_id as card identifier, which allows preferring non-UB card images
- Big removal of dead code

---

## 1.2.1
- New detection preview screen
- Fixed the Scryfall download pop-up so it always appears when the database is empty
- Fixed pop-up timing issues on launch
- Fixed overflow on small devices
- Fixed matching when single-sided card names collide with multi-face card names
- Advertising no longer happens when the draft is fully seated
- Some bluetooth edge case fixes
- Removed the non-functional Cubecobra button

## 1.2.0
- Added a debug mode for easier testing of new features
- Rewrote deck image sharing, now runs 10-20x faster
- Some deck scanner optimizations (should be faster)
- Fixed the "New set available on Scryfall" prompt
- Updated Settings > Cubes page. Prep work for upcoming features

## 1.1.9
- Fixed a Scryfall API issue

## 1.1.8
- Users should get a pop-up reminding them that a new set is available before prerelease weekend

## 1.1.7
- You can now specify a deck's W/L/D instead of just W/L
- Decks without a color identity now show the colorless mana symbol in the overview
- We now get a list of set release dates from Scryfall, and get a notification when there's a new one available for download

## 1.1.6
- Updated the tflite library to resolve a 4kb page file issue
- Fixed a layout issue on small devices
- Updated all libraries

## 1.1.2
- Small bugfixes

## 1.1.1
- Bugfixes

## 1.1.0
- You can now add a sideboard to your draft deck. Uploads to Cubecobra should also include this sideboard, and deck imports/exports should work with the standard text formats for decklists with sideboards

## 1.0.3
- Fixed a Welcome screen bug

## 1.0.2
- Updated the welcome screen, and made the Scryfall download mandatory for further app use

## 1.0.1
- Small bugfix version bump

## 1.0.0
- Images used for detection are now saved and viewable from the deck, and are included in any backups
- With this final feature, the main functionality is covered and we're ready for a proper release!

## 0.6.2
- Deck photos can now be shared from other apps using the OS share system (iOS & Android)

## 0.6.1
- When scanning a picture, we now determine the best orientation automatically by checking which has the most detections
- Updated the image processing screen to freeze less during loading

## 0.6.0
- When adding a deck and fine-tuning the detection results, newly added cards are now blank instead of Fblthp
- Decks can now be tagged, the tags are shown in the overview, and you can filter your decks by tag
- Added the option to filter by deck colors
