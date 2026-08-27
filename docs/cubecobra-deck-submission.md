# Plan: Submit single decks to CubeCobra (bundled per cube)

## Goal
Let users submit cube-linked decks from the Deck Manager to CubeCobra, bundling decks into a single reusable per-cube record (`"SnapDrafter decks"`), with the entire flow (sign-in, progress, result) presented in a dialog. No snackbars.

## Verified CubeCobra API (from dekkerglen/CubeCobra server source)

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /cube/records/analysisdata/:cubeId` | cookie (no middleware; `isCubeViewable`) | All records for cube: `{records: [{id, name, date, players: [{name, userId}], matches, trophy, decks: {playerName: [oracleIds]}}], cards}` |
| `POST /cube/records/create/:cubeId` | cookie + csrf | Create record; form field `record` = JSON `{name, date, description, players[], matches[], trophy[]}`; **Joi cap: 16 players**, name ≤255 chars; redirects to `/cube/record/<id>` |
| `GET /cube/records/sharetoken/:recordId` | cookie | `{token}` (403 if unauthorized) |
| `POST /cube/records/contribute/:recordId` | share token only | `{token, mainboard: JSON[], sideboard: JSON[], newPlayer, wins, losses, draws, nickname}`; appends player + deck seat; 302→`/404` = rejected/deleted |

- Deck↔record linkage (server-side): `contribute` appends player to `record.players`, stores W/L/D in `record.overrides`, and puts the decklist in that player's seat of the record's linked `Draft` (auto-created as `UPLOAD`). One deck = one player seat; no standalone-deck variant.
- `analysisdata` decklists are deduped to unique oracle ids server-side → cannot exact-multiset compare; use player-name based dedup only.
- Bundle marker = record `name == "SnapDrafter decks"`. Rollover to a fresh record when `players.length >= 16`.

## Implementation

### 1. Service — `lib/services/cubecobra_api.dart`

**Model** (top-level, near existing classes):
```dart
class CubeRecordSummary {
  final String id;
  final String name;
  final int date;
  final List<String> playerNames;
}
```

**New: `fetchCubeAnalysisData(String cubeId, String cookie)`**
- `GET $_baseUrl/cube/records/analysisdata/$cubeId` with `_formHeaders(cookie: cookie)`
- 404 → `CubeCobraApiException('Cube not found or not viewable')`; other non-200 → `CubeCobraApiException`; login redirect in body/location → `CookieExpiredException`
- Map `records` → `List<CubeRecordSummary>` (guard against missing/null fields)

**New: `submitDeckToCube({required cubeId, cookie, deckName, mainboardOracleIds, sideboardOracleIds, wins, losses, draws, required void Function(String step) onProgress})` → `String` (recordId)**
1. `onProgress('Resolving record…')` → `fetchCubeAnalysisData` → `findNewestBundleRecord(records)` (pure helper, see below). If found and `playerNames.length < 16` → reuse id; else `onProgress('Creating new record…')` → `createRecord` with `{"name": "SnapDrafter decks", "date": now, "description": "Decks submitted from SnapDrafter", "players": [], "matches": [], "trophy": []}`.
2. `onProgress('Uploading deck…')` → `getShareToken` → `contributeDeck(playerName: <unique name>, wins/losses/draws, ...)`.
3. Retry-once: if contribute or sharetoken fails with record-not-found (`302→/404` flash or 403), clear the resolved id, skip straight to `createRecord`, retry contribute once; rethrow if it fails again.
4. Returns the final recordId.

**Pure helpers** (top-level, unit-testable):
```dart
CubeRecordSummary? findNewestBundleRecord(
    List<CubeRecordSummary> records, {String bundleName = 'SnapDrafter decks'});
String makeUniquePlayerName(String name, Set<String> existingNames); // "Name", "Name (2)", …
```

Existing members reused unchanged: `login`, `validateCubeAuth`, `createRecord`, `getShareToken`, `contributeDeck`, exceptions, `_formHeaders`.

### 2. Dialog — new `lib/widgets/cubecobra_submit_dialog.dart`

`Future<void> showCubeCobraSubmitDialog(BuildContext context, {required Deck deck, String? cubeName})`

Follows the repo's dialog convention (`showDialog` + `AlertDialog` + `StatefulBuilder`; cf. `deck_edit_dialog.dart:74`, `cubecobra_submission_card.dart:175`). Scrollable `AlertDialog`, title row = CubeCobra SVG icon + "Submit to CubeCobra", subtitle "Deck: <name> · Cube: <cubeName>".

Internal state machine (enum + fields, mirroring `CubeCobraState`):
1. **checking** — spinner while loading `cc_auth_<deck.cubecobraId>` from SharedPreferences; missing → **signInRequired**; present → `validateCubeAuth`.
2. **signInRequired** — inline username/password fields + Sign In button (reuse logic from `_showInlineSignInDialog`: `login` → `validateCubeAuth` → persist `CubeCobraCredentials`; `notOwner` → **notOwner**; success → **ready**). Inline error text in-dialog.
3. **notOwner** — message "Signed in as <user>, but this account does not own <cube>" + "Sign in with Owner Account" (back to **signInRequired**).
4. **expired** — inline password-only re-auth form (pattern from `_buildReAuthCard`), success → **ready**.
5. **ready** — explanation text ("Will be added to your SnapDrafter decks record for <cube>; a new record is created when the current one is full."), shows deck W/L/D, Submit button.
6. **submitting** — Submit disabled; step checklist rendered from `onProgress` calls (3 steps: Resolving record / Creating new record / Uploading deck), each with pending/check/error icon + latest message (style from `_buildProgressCard`, `cubecobra_submission_card.dart:548`).
7. **success** — green check, "Submitted to cube/record/<recordId> · N decks in record" (N from analysisdata + 1), "View on CubeCobra" (`launchUrl` to `https://cubecobra.com/cube/record/<id>`), Close button.
8. **failure** — inline error text (no snackbar), Retry (re-runs submit) + Close.

Dialog is non-dismissible (`barrierDismissible: false`) while in **submitting** (toggle via `setDialogState`). On success/failure allow dismiss via buttons.

### 3. Entry point — `lib/screens/deck_viewer.dart`

- Replace the commented-out CubeCobra `IconButton` (lines 355–367) with a working one: `onPressed: () => showCubeCobraSubmitDialog(context, deck: deck, cubeName: <cube name>)`.
- Cube name: reuse existing `_cubes` lookup used at `deck_viewer.dart:103`.
- When `deck.cubecobraId == null` → button disabled with `tooltip: 'Only cube-linked decks can be submitted'` (records are cube-bound).
- Remove/leave the old `shareWithCubeCobra` browser-import helper (`deck_viewer.dart:1339`) as-is (unused legacy path).

### 4. Tests — `test/cubecobra_submit_test.dart` (new)
- `findNewestBundleRecord`: none → null; multiple → newest `date`; respects `bundleName`; skips records missing name/date.
- `makeUniquePlayerName`: plain, collision → `(2)`, multiple collisions, empty name fallback.
- (No network tests; service calls verified manually.)

## Edge cases
- Record full (16 players) → fresh record created; old record stays untouched.
- Stored bundle record deleted on CubeCobra → contribute/share fail → retry once on a fresh record.
- Duplicate deck names in one record → `makeUniquePlayerName` suffix.
- Expired cookie mid-dialog → re-auth form; `CookieExpiredException` surfaced in-dialog.
- Deck with empty mainboard → block submit with in-dialog message.
- Large cubes → analysisdata payload ~1.5–8 MB worst case, fetched once per submission; acceptable, noted as future optimization (gzip/cache).

## Verification
1. `flutter analyze`
2. `flutter test`
3. Manual, with a real CubeCobra account:
   - Fresh account/no bundle → creates `"SnapDrafter decks"` record, deck appears on cube's Draft Reports
   - Second deck → same record, 2 players
   - Same deck name twice → `(2)` suffix
   - Pre-fill a bundle to 16 players → next submit rolls a new record
   - Expired cookie → re-auth form in dialog
   - Set-only deck → button disabled

## Files touched
- `lib/services/cubecobra_api.dart` (add model + 2 functions + 2 pure helpers)
- `lib/widgets/cubecobra_submit_dialog.dart` (new)
- `lib/screens/deck_viewer.dart` (button wiring)
- `test/cubecobra_submit_test.dart` (new)
- `docs/cubecobra-deck-submission.md` (this plan)
