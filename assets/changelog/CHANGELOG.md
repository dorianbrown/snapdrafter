# SnapDrafter Changelog

`2026-08-28`

## 1.2.3

#### Features
- Added a "Submit deck to CubeCobra" button to the deck viewer (behind the share icon)
- Added a changelog to the settings menu
- On first launch and after updates, there's a pop-up with recent changes

---

`2026-08-18`

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

`2026-07-25`

## 1.2.1

#### Features
- New detection preview screen

#### Bugfixes
- Fixed the Scryfall download pop-up so it always appears when the database is empty
- Fixed pop-up timing issues on launch
- Fixed overflow on small devices
- Fixed matching when single-sided card names collide with multi-face card names
- Advertising no longer happens when the draft is fully seated
- Some bluetooth edge case fixes

#### Other
- Removed the non-functional Cubecobra button

---

`2026-07-24`

## 1.2.0

#### Features
- Added a debug mode for easier testing of new features

#### Bugfixes
- Fixed the "New set available on Scryfall" prompt

#### Other
- Rewrote deck image sharing, now runs 10-20x faster
- Some deck scanner optimizations (should be faster)
- Updated Settings > Cubes page. Prep work for upcoming features

---

`2026-03-08`

## 1.1.9

#### Bugfixes
- Fixed a Scryfall API issue

---

`2026-03-02`

## 1.1.8

#### Features
- Users should get a pop-up reminding them that a new set is available before prerelease weekend

---

`2026-02-16`

## 1.1.7

#### Features
- You can now specify a deck's W/L/D instead of just W/L
- Decks without a color identity now show the colorless mana symbol in the overview
- We now get a list of set release dates from Scryfall, and get a notification when there's a new one available for download

---

`2026-02-09`

## 1.1.6

#### Bugfixes
- Updated the tflite library to resolve a 4kb page file issue
- Fixed a layout issue on small devices

#### Other
- Updated all libraries

---

`2026-02-08`

## 1.1.2

#### Bugfixes
- Small bugfixes

---

`2026-02-08`

## 1.1.1

#### Bugfixes
- Bugfixes

---

`2026-02-08`

## 1.1.0

#### Features
- You can now add a sideboard to your draft deck. Uploads to Cubecobra should also include this sideboard, and deck imports/exports should work with the standard text formats for decklists with sideboards

---

`2025-09-04`

## 1.0.3

#### Bugfixes
- Fixed a Welcome screen bug

---

`2025-09-04`

## 1.0.2

#### Features
- Updated the welcome screen, and made the Scryfall download mandatory for further app use

---

`2025-09-02`

## 1.0.1

#### Bugfixes
- Small bugfix version bump

---

`2025-09-02`

## 1.0.0

#### Features
- Images used for detection are now saved and viewable from the deck, and are included in any backups

#### Other
- With this final feature, the main functionality is covered and we're ready for a proper release!

---

`2025-08-31`

## 0.6.2

#### Features
- Deck photos can now be shared from other apps using the OS share system (iOS & Android)

---

`2025-08-27`

## 0.6.1

#### Features
- When scanning a picture, we now determine the best orientation automatically by checking which has the most detections

#### Bugfixes
- Updated the image processing screen to freeze less during loading

---

`2025-08-22`

## 0.6.0

#### Features
- Decks can now be tagged, the tags are shown in the overview, and you can filter your decks by tag
- Added the option to filter by deck colors

#### Bugfixes
- When adding a deck and fine-tuning the detection results, newly added cards are now blank instead of Fblthp
