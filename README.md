# TCGX

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
- **Me** (`lib/screens/me`) — profile/settings tab, including the testing
  "AI (testing)" switch (card recognition via OpenAI or DeepSeek) and the
  "Try AI scan" / "Try AI binder scan" screens. Those are the only network calls; see `lib/pricing/`
  and `lib/state/ai_settings.dart`. Keys go in the gitignored
  `lib/dev_secrets.dart` (template: `lib/dev_secrets.example.dart`).
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

A card number is not a collectible: `rarity` is the official printed rarity,
and `PrintingVariant` (`lib/models/printing_variant.dart`) says which physical
printing it is (family, specific name, artwork). Unknown is not base, and
pricing refuses unknown printings. Marketplace wording (e.g. Yuyu-tei's
`(パラレル)`) lives only in that marketplace's adapter.

Exact-printing resolution (`lib/pricing`): vision recognition only DESCRIBES the
photo (`VisualObservation`: treatment colour, background style, manga panels,
frame, foil, markers) and PREDICTS a printing - a hypothesis marked
`PrintingSource.visionHypothesis`, which pricing refuses.
`PrintingResolutionService` then finds the card's known `PrintingCandidate`s
(`printing_candidates` cache, else live-web-search `PrintingResearchService`,
evidence URLs verified) and picks the one the photo fits; only a resolved
printing is priced (`CardIdentifier` chains the two). Official rarity, our
canonical variant name and marketplace aliases are kept separate; aliases only
find and match listings (longest alias wins, so "Manga Rare" never claims a
"Red Manga Rare" listing). AI Scan Test shows every step.

Japanese One Piece pricing (`lib/pricing`): `JapanesePriceResearchService`
asks `YuyuteiPriceSource`, `CardRushPriceSource` and `EStarboxPriceSource`
(each a `JapanesePriceSource`) about the exact printing, then falls back to
the live web search if none has it. Each source owns its site's search,
parsing and verified labels; observations are saved by
`PriceObservationRepository` (`price_observations`, append-only).

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
