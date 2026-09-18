# Pokédex TCG Collection

A Flutter app for cataloguing a physical Pokémon TCG card collection: capture
a card with the camera, file it under a set (release) and optional
sub-folder, track condition/copies/price paid, log value over time, and mark
cards for trade or wishlist. Everything is local — SQLite on-device via
`sqflite`, no server, no account, no sync.

## App structure

- **Collection** (`lib/screens/home`) — releases (sets) the user has added,
  an "unsorted" tray for cards not yet filed, running totals for card count
  and estimated value.
- **Sets** (`lib/screens/sets`, `lib/screens/folder`) — browse a release's
  sub-folders and cards.
- **Trade** (`lib/screens/trade`) — cards marked `forTrade`.
- **Me** (`lib/screens/me`) — profile/settings tab.
- **Card detail** (`lib/screens/card_detail`) — a single card's info, photo,
  and value history (chart via `fl_chart`), with a sheet to add a new value
  entry.
- **Capture flow** (`lib/screens/capture`) — camera capture → crop/retake →
  batch triage (multiple cards in one pass) → assign to a release → name/tag
  → file. `capture_route.dart` defines a shared route name so these screens
  can pop back without importing each other.
- **Add manual** (`lib/screens/add_manual`) — add a card without the camera.
- **Search** (`lib/screens/search`) — search across the collection.

## Data layer

- `lib/data/app_database.dart` — opens/migrates the single SQLite database
  (`pokedex_tcg.db` in the app's documents directory). Tables: `releases`,
  `sub_folders`, `cards`, `value_entries`.
- `lib/data/collection_repository.dart` — CRUD for releases, sub-folders,
  and cards (create/update/delete/move).
- `lib/data/value_repository.dart` — per-card value entries over time (for
  the value graph and portfolio total).
- `lib/data/photo_store.dart` — saves captured/cropped photos to disk.
- `lib/state/app_state.dart` — a `ChangeNotifier` (via `provider`) holding
  cross-cutting state (release list, unsorted count, totals). Per-screen
  data (a release's cards, search results) is queried directly from the
  repositories rather than cached here, since collections can run to
  thousands of cards.

## Models

`TcgCard`, `Release`, `CardCondition` (NM/EX/GD/PL), `CardLanguage`
(JP/ENG/CN/KR), `ValueEntry` — see `lib/models/`. A card's rarity/kind/
color/type options are controlled per `ReleaseCategory` (Pokémon/One
Piece/Others) — see `CardFieldOptions`.

## Running it

```bash
flutter pub get
flutter run
```

Tests use `sqflite_common_ffi` to run the database in-memory outside a device.

```bash
flutter test
```

## Changelog

User-visible and structural changes are tracked in
[CHANGELOG.md](CHANGELOG.md). See `CLAUDE.md` for the policy — every change
made through Claude Code gets an entry.
