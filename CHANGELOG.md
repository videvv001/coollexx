# Changelog

All notable changes to this project are documented here, newest first.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [1.8.0] - 2026-10-05

### Added
- Exact-printing resolution: after the vision model reads a card, it is matched
  against that card's known printings (found by live web research, cached 30
  days in the new `printing_candidates` table) by what the photo shows - so a
  red-treatment manga card resolves to its Red Manga print instead of the
  ordinary Manga one. No card numbers or printing names are special-cased.
- Recognition now reports what it sees (treatment colour, background style,
  manga panels, frame, foil, markers) in a fixed vocabulary shared with printing
  research, and the AI Scan Test screen shows vision's guess, the known
  printings, the evidence, the rejected printings and the price query.
- Wrong-printing guard for web-search prices: a listing worded like another
  printing of the same card is shown but not used.

### Changed
- The vision model's printing name is a prediction only; pricing refuses it
  until it is resolved (`PrintingSource`). Low printing confidence no longer
  automatically asks for an angled photo - that is requested only for
  foil/texture doubt (`UncertaintyReason`).
- Recognition schema: `predicted_variant_*`, `visual` and `uncertainty_reasons`
  replace `variant_*` and `evidence_needed`. Database schema is now v9.

## [1.7.0] - 2026-10-05

### Added
- Japanese One Piece prices now come from three marketplaces — YuYu-tei,
  CardRush and e-Starbox — each asked about the exact printing, in parallel.
  One failing or finding nothing never fails the rest. Each listing keeps its
  marketplace's own label, URL, source type and match confidence.
- e-Starbox is read as a price-comparison source (`PRICE_COMPARISON`), its
  buyback table is ignored; CardRush graded and condition-grade copies are
  shown but never priced.
- The price result lists, per marketplace, whether the exact printing was
  found, not found, undecidable or failed to load, and marks every other
  listing NOT USED with the reason.
- Append-only price history (`price_observations`, DB v8): every observation
  of a research is saved with its printing, marketplace, URL, source type,
  raw label, price and match confidence, and is only ever read back for that
  exact printing. Written from the AI scan/binder test screens.
- `dart run tool/japanese_price_spike.dart [base|parallel|crew]` runs one live
  lookup against the three marketplaces.

### Changed
- When no marketplace has the exact printing, the live web search runs as a
  fallback with the full printing, its artwork and discovery search terms; its
  sources are credited to the marketplace their URL belongs to.
- Prices are only combined within one kind (sale, market, asking); sold-out
  listings count only when nothing is in stock; a wide spread between exact
  matches is flagged and lowers confidence.

### Fixed
- EB04-061's crew-background print was reported as "not listed" at YuYu-tei:
  it is an OP17 pack card, listed only on OP17's page, and the lookup built
  the set page from the number prefix. YuYu-tei is now searched by number
  across all sets, and the print is matched by its own label.

## [1.6.0] - 2026-10-05

### Added
- Cards now record which physical printing they are (`TcgCard.variant`:
  family base/parallel/super parallel/special/promo/other/unknown, a specific
  printing name, and an artwork note), stored in three new nullable `cards`
  columns (DB v7). Card number and rarity can't tell printings apart (EB04-061
  is one SEC with a base, a parallel and a crew-art print). Existing cards
  migrate as *unknown*, never base. Editable under "Printing" on Edit card.
- AI recognition returns the printing (family, name, artwork description,
  visible markers, candidates) and separate `logical_card` / `exact_printing`
  confidences, so the artwork it saw is kept instead of being flattened into
  one variant string.

### Changed
- Pricing refuses an unknown printing (`PrintingVerificationRequired`) instead
  of treating it as base, in both the Yuyu-tei and AI research services.
- Yuyu-tei matching reads each listing's full `(…)` suffix list and prices a
  printing only on an exact verified label + rarity match (base, parallel
  today). Anything else is `InsufficientEvidence` with the listings shown.

### Fixed
- A super parallel / crew-art print was priced as the plain parallel whenever
  Yuyu-tei listed just one alternate (EB04-061: 5,980円 instead of "no listing").
- Copying a card to another folder now carries its printing over.

## [1.5.1] - 2026-10-04

### Added
- Price results now show the last sold price (with its date) and the lowest
  current listing next to the estimate, and the AI search is asked to look for
  both. Binder scan cards show them too.
- Prices found in another currency (e.g. an EUR eBay sale) are converted to
  the requested one at the live ECB rate (frankfurter.dev, fetched alongside
  the search, so no extra wait) instead of being thrown away; the page's own
  price is shown as "converted from". The rate is never taken from the model,
  and if the rate lookup fails such sources are excluded as before.

### Changed
- English price research is limited to TCGplayer and eBay (USD), about half
  the time of an open-web search (17s -> 9-13s measured). Change the sites in
  `PricingConfig.sourceRules`.

## [1.5.0] - 2026-10-04

### Added
- Dev-only slot for the DeepSeek API key: `lib/dev_secrets.dart` is
  gitignored (copy it from `lib/dev_secrets.example.dart`), so the key never
  lands in the repo while the recognition provider is wired up for testing.
- Live price research groundwork: a `PriceResearchService` interface with an
  OpenAI implementation that forces a live web search (Responses API
  `web_search`, `tool_choice: required`) and returns a typed result. A
  response without a completed search is never accepted as a price, source
  URLs the search didn't visit are dropped, and the estimate/range are
  computed from the kept sources rather than taken from the model. Not yet
  wired into any screen; `dart run tool/price_research_spike.dart` runs one
  real research call. Key goes in `openaiApiKey` in `lib/dev_secrets.dart`.
- AI card recognition behind a `CardRecognitionService` interface, with
  OpenAI (`gpt-6-luna`) and DeepSeek (`deepseek-flash`, DeepSeek-V4.1-Flash)
  implementations. A confident card with an uncertain printing (unknown
  language/variant, or printing confidence under the configured threshold)
  comes back as "needs verification", never as a match.
- Me tab: "AI (testing)" switch to pick the recognition provider, and a
  "Try AI scan" screen (photo or upload → recognition → editable details →
  live price research with sources). Nothing it does is saved.
- Price research provider is a testing switch too (OpenAI / DeepSeek). The
  same "no proof of a live search → no price" check applies to both. A real
  DeepSeek call confirmed its API runs no search: it returned no search step
  and itself replied that no web-search tool was available, so it can't
  supply live prices; its answer stays visible in the raw response.
- New "Scan binder" option on both the Collection and the folder add menus,
  alongside Take a photo / Upload from gallery. Photograph a binder page or
  pick several page images at once, and the app finds every card on each
  one, corrects its perspective and crops it out upright. Keep adding pages
  - photos and uploads mixed freely - then save the lot in one go.
- Binder scan results are reviewable before anything is saved: each page
  shows its detected cards outlined on the page image, with the crops it
  produced underneath. Drop a card the detector got wrong, drop a whole
  page, or retry a page that failed, then hand the rest to the same batch
  triage screen a burst capture ends on - OCR autofill, renaming and
  assigning to a release all work exactly as they already did.
- A page that can't be read, or that yields no cards, is reported on its own
  without costing you the pages already scanned; multi-page uploads show
  which page is being processed and what it found as they go. Leaving with
  unsaved cards prompts the same save/discard choice the camera does, and
  the scan survives backgrounding and process death like a burst does.
- Me tab: "Try AI binder scan". Photograph or upload a binder page; the cards
  are found on-device, every one is recognized by the AI at once (three at a
  time), and "Research prices" prices all the confidently identified ones in
  one go. Tap any card to open it in the single-card screen to correct it.
  Saves nothing.
- Japanese One Piece prices now come straight from Yuyu-tei's set page
  (`YuyuteiPriceService`) instead of an AI web search: about 1s instead of
  8-17s, in yen, whichever research provider is picked. A search limited to
  yuyu-tei.jp was tried first and finds only the shop's news/FAQ pages, never
  card listings. A regular printing is priced; for an alternate printing it's
  priced only when the number has exactly one, otherwise every printing
  Yuyu-tei lists is shown to pick from. Other games/languages are unchanged.
- `PricingConfig.sourceRules`: optional per-language site allowlist for the AI
  price search (empty by default), which also sets the currency to expect.
- `price_research_spike.dart jp` researches the Japanese printing.

### Changed
- App renamed to TCGX (launcher label and in-app title); package name and
  database file are unchanged so existing installs keep their data.
- App font is now Plus Jakarta Sans, bundled in `assets/fonts/` so it works
  offline.
- Binder card detection runs entirely on-device in pure Dart (no OpenCV, no
  network) on a background isolate. It separates cards from the dark pockets
  around them by brightness, measured against a local rather than a
  page-wide threshold so an unevenly lit page doesn't lose its dim corner,
  and tests each candidate against its convex hull so a card whose dark
  artwork reaches its own border is still found whole. Measured at 24 of 24
  cards across three real hand-held binder photos - tilted, glare-blown,
  with empty slots - plus one background shape wrongly offered as a card,
  which is one tap to remove in review.
- A pending capture item's sequence number is now one past the highest so
  far rather than the item count. Identical for a burst, which only ever
  appends, but binder scan can drop a card mid-session, and a count would
  then reuse a live sequence and scramble the order cards are read back in.

### Fixed
- Card recognition no longer gives up when the card number is too small to
  read: it now identifies the card from artwork, name, power/cost, color and
  set symbol and infers the number. An inferred number only counts as
  identified above the printing-confidence threshold; below it the card comes
  back as "needs verification" with the number editable.
- The Me-tab smoke tests mock shared_preferences and scroll to the footer, so
  they no longer fail on the settings providers and the longer Me list.
- Release APKs now request the INTERNET permission; only debug/profile
  builds had it, so any network call would have failed in a release build.

## [1.4.0] - 2026-09-23

### Added
- Guided card scan and Quick burst/unsorted-tray triage now prefill
  name/number/language (and One Piece kind) from on-device text recognition
  of the card photo — runs entirely on the phone, no server involved, reads
  both Latin and Japanese print, and the fields stay editable so it's only
  ever a starting suggestion.
- Scanning a card whose category can't already be told from a bound release
  now asks once (Pokémon / One Piece / Others) so OCR knows where on the
  card to look; picking Others just skips the auto-fill for that card/batch.
- New "Auto-fill from photo (OCR)" toggle on the Me tab to turn scanning
  (and its category prompt) off entirely for collectors of other games.
- Uploading from a folder now takes multiple images at once. A single pick
  still goes through crop → name & file; several go to batch triage, the
  same screen a burst lands on, pre-filed into that folder. Both ends
  already run OCR autofill, so gallery uploads get it in either place.
- Tap-to-focus on the camera preview (both Quick burst and Guided scan) —
  sets focus and exposure to the tapped point, with a brief ring where you
  tapped. Silently no-ops on devices that don't support it.

### Changed
- The shared photo editor (card photos, release covers, and the crop/retake
  step in capture) now has separate rotate-left and rotate-right buttons
  instead of a single clockwise-only rotate.

### Fixed
- Card detail/preview now shows Kind for Pokémon and One Piece cards, and
  Color for One Piece cards — those fields are captured on add and editable
  from Edit card, but were silently missing from the preview grid.
- Rotating or saving a photo in the shared editor no longer freezes the app:
  the JPEG decode/rotate/crop/encode work (slow in pure Dart on a full-res
  camera photo) now runs on a background isolate instead of blocking the UI
  thread, so the spinner actually animates and the screen stays responsive
  while it works.
- Finishing a sort no longer drops you on a black screen: assigning the
  unsorted tray to a release (and saving a gallery upload from a folder)
  popped every route off the tab's navigator, because the route name the
  capture flow pops back to only existed when the flow started at the
  camera. Capture flows now all mark their entry route, and the pop stops
  at the tab root if one is ever missed.
- OCR no longer mistakes a card's kind banner, trait line or effect text
  for its name. A card's lower portion stacks kind / name / trait / ID, so
  "text near the bottom" was never enough — the name is now identified by
  its relationship to the kind banner (the block directly beneath it),
  with effect prose, IDs and kind labels ruled out first. Kind labels come
  from the app's existing `CardFieldOptions.kind` list rather than a
  second list kept in the scanner, and an ambiguous read now reports no
  name instead of guessing. Covered by `test/card_text_layout_test.dart`.
- Scanning into a folder no longer silently skips OCR. A release's category
  of "Others" was being treated as a definitive "don't autofill", but it's
  also what every release gets when nobody picked a category, so scanning
  inside such a folder neither autofilled nor asked — while the same scan
  outside a folder worked. Only Pokémon/One Piece now count as a definitive
  answer; anything else falls back to the category prompt.
- Folder Category is now editable from both "Edit folder" on My Collection
  and the folder's own rename dialog, so a folder created without picking
  one (it silently defaulted to "Others") can be corrected — and set once,
  it stops the prompt asking again.
- Gallery uploads now copy the picked image into the app's own storage
  instead of pointing at the picker's temp file, which the OS can delete
  out from under a saved card.

## [1.3.0] - 2026-09-21

### Added
- Collection folders now remember their own sort (Favorite, Recent, Rarity,
  or ID with Ascending/Descending) independently per folder, via a new Sort
  button next to the folder's Display View toggle. ID sorting is
  numeric-aware (`OP14-2` sorts before `OP14-10`), Rarity uses the existing
  per-category rarity hierarchy, and a folder that's never been sorted
  defaults to ID Ascending.

### Changed
- Collection folder grid now shows 3 columns on mobile (was 4) in both Grid
  and Grid-with-details display modes.
- Folder Favorite now toggles from a directly clickable star in the upper-
  left corner of the folder cover on My Collection — the same look and touch
  behavior as the collection-card favorite star — instead of via the folder
  long-press menu.

### Removed
- The redundant "Select" button inside a folder screen; long-pressing a
  card already enters selection mode, which is now the only way in.
- "Add/Remove from favorites" from the folder long-press menu, superseded by
  the folder's own clickable favorite star.

## [1.2.0] - 2026-09-21

### Added
- Burst-mode camera captures are now protected against data loss: every
  shot is recorded in a persistent capture session the moment it's taken
  (not just held in the camera screen's own memory), so tapping another
  bottom-nav tab, pressing Back, backgrounding the app, or the app getting
  killed no longer loses a batch of captured photos. Leaving the camera
  with unsaved photos — a tab switch or Back — now prompts to continue
  capturing, save & leave, or discard; leaving via Home does neither (every
  shot is already safe, so there's nothing to confirm) and just releases
  the camera hardware until you return. If the app was killed mid-session,
  the next launch offers to recover or discard whatever was captured.
  "Done · review" now commits the session into real collection entries in
  a way that's safe to retry if interrupted (e.g. a crash mid-save) —
  already-committed shots are never duplicated.

## [1.1.0] - 2026-09-21

### Added
- A folder's camera FAB is now a `+` "Add collection" menu offering Take a
  photo (the existing camera), Upload image, or Add without image, so a
  card can be filed without ever opening the camera. Upload image reuses
  the same gallery picker and crop editor covers use, then the existing
  name/tag/file screen, pre-filed into the current folder; Add without
  image opens the existing "Add without a photo" screen the same way.
- The camera's card-guide brackets are now a real, adjustable live capture
  frame: pinch to zoom uses the camera's own native zoom (not a scaled-up
  preview), and the frame always shows exactly the region that will be kept
  in the saved photo, computed from the same aspect-ratio math on both
  sides. Zoom persists for the whole camera session and across every shot
  in a burst — set it once, keep shooting — with a small reset control to
  return to the default. Guided Scan's forced crop-after-every-shot step is
  gone (the shot already arrives framed); its crop editor is now an
  optional "Re-edit" instead. Applies to Quick burst, Guided scan, and
  Single alike, since they all share one capture path. The crop itself runs
  off the UI thread so burst shooting doesn't stall.
- A third folder display mode, "Grid with details", alongside the existing
  Grid and List: the same image grid with name (left) and card number
  (right) below each photo, ellipsized rather than overlapping when either
  runs long. The view-mode toggle now cycles Grid → Grid with details →
  List → Grid, and the chosen mode is remembered across folders and app
  restarts (same `shared_preferences` pattern My Collection's own display
  toggle already uses). Favorites and Select mode work unchanged in all
  three modes.
- Folders can be marked Favorite: a "★ Add/Remove from favorites" entry in
  the folder long-press menu (persisted `isFavorite` column on `releases`,
  defaulting to `false` for existing folders via a v5 migration), a small
  star badge on favorited folder cards in both landscape and portrait
  display modes, and a new "Favorite" sort option on My Collection that
  groups favorited folders first, sorted by date within each group.
- My Collection search now matches folder names (case-insensitive, partial)
  alongside the existing card search, shown as a "Folders" section above the
  card grid results; tapping a folder result opens it exactly like tapping
  it from My Collection.
- Move and Copy a collection entry to a different folder: available from a
  card's own action menu ("Move to folder"/"Copy to folder") and, for
  multi-selected cards, from the folder screen's selection toolbar. Move
  reassigns the existing entry's folder in place; Copy inserts an
  independent entry (its own id, its own photos/condition/notes/etc. carried
  over) so the original is untouched. Both use a new shared destination
  picker (cover thumbnail, name, card count, searchable once a collection
  has more than a handful of folders); Move hides the card's current folder
  from the picker. A snackbar confirms the destination afterwards.
- Edit Folder's landscape/portrait cover pencil now offers "Adjust image"
  above "Take a photo"/"Choose from gallery" whenever that orientation
  already has a cover, reopening the existing crop/reposition screen on the
  current image instead of forcing a re-pick. Hidden when the orientation
  has no image yet. Reuses the same picker sheet and `PhotoEditorScreen` as
  every other cover/photo flow — no separate crop implementation.
- Long-pressing a folder on My Collection now opens an Edit/Delete menu
  (replacing the old edit-pencil badge). Delete asks for confirmation,
  naming how many cards will go with it, then deletes the folder together
  with every card filed under it in one transaction — no more orphaned
  collection entries left behind (and no more "cards need a folder" banner
  caused by a folder delete). The folder's own cover images are cleaned up
  too. Same cascading delete now backs the "Delete" item in a folder's own
  "..." menu.
- A shared `confirmDelete` dialog (Cancel/Delete, destructive styling, safe
  defaults on back-button/outside-tap) now backs every destructive delete in
  the app: folder delete, card delete, bulk bin, batch-triage bin all, and
  swiping away a value-history entry (which previously deleted immediately
  with no confirmation).

## [1.0.2] - 2026-09-21

### Fixed
- Edit Folder's landscape/portrait cover picker (Camera/gallery source sheet,
  then the crop screen) rendered behind the Edit Folder dialog instead of
  above it, making it unusable. Cause: `AppShell` gives each bottom tab its
  own nested `Navigator`; `showDialog` defaults to opening on the app's root
  Navigator while `showModalBottomSheet`/`Navigator.push` default to the
  nearest Navigator to whatever context they're given — the cover-picker
  code closed over the tab's own context (captured before the dialog
  opened), so the picker and crop screen landed one Overlay layer below the
  dialog. Both now explicitly target the root Navigator
  (`useRootNavigator: true` / `Navigator.of(context, rootNavigator: true)`),
  matching where the dialog itself lives.

## [1.0.1] - 2026-09-21

### Added
- Release folders now support separate landscape and portrait covers,
  each independently croppable, instead of one cover image locked to a
  single orientation. Picking a cover for one orientation defaults the
  other to a centered crop of the same photo, so a single image is enough
  unless you want two different ones. Edit Folder shows both previews at
  their real aspect ratio; the in-folder "Set cover photo" flow now writes
  into the same landscape/portrait fields, so there's one cover system, not
  two. Existing folders with only the old single cover keep working via a
  fallback to it until edited.
- My Collection has a landscape/portrait display toggle next to
  Search/Sort/Filter, remembered across restarts, that switches both the
  grid's card shape and which cover each folder shows.

### Fixed
- My Collection folder cards could overlap the row below them: the grid
  used one fixed aspect ratio for every cell while each folder's cover
  rendered at its own (portrait or landscape) aspect ratio, so a portrait
  cover's taller content overflowed its cell. The grid now derives its
  aspect ratio from the actual cover shape and a fixed text-block budget,
  so cells always reserve enough height.

### Changed
- Card detail screen redesigned to a compact, wireframe-driven layout: a
  swipeable image carousel (position badge, prev/next arrows, tap-through to
  the existing full-screen viewer) with the copy count as a badge on the
  image itself; a category-driven metadata grid (ID, Release/Language,
  Rarity(/Type), Condition) built from a small per-`ReleaseCategory` field
  table (`card_metadata_fields.dart`) so a new category (Yu-Gi-Oh!, Magic,
  Sports, ...) is a one-entry addition, not a new branch in the UI; and a
  Value section with Add/History as icon buttons instead of a separate
  bottom button and text link. The inline copies +/- stepper and condition
  chips move to the existing Edit screen, which already edits both.
- Value chart now plots a fixed 12 calendar-accurate periods (current day/
  week/month/year plus the previous 11) instead of a user-picked count of
  rolling 30/365-day-approximated windows, using each period's *latest*
  entry rather than a mean — matches how a value-over-time chart should
  read. The Y-axis now shows real, auto-scaled monetary values (e.g. $250,
  $1K, $1.5K) instead of being hidden, and is zero-based to match the
  redesigned chart.

### Added
- Release folders can be edited after creation: press and hold a folder on
  My Collection to reveal an Edit icon, which opens a modal pre-filled with
  the folder's cover image, name, and language — Save updates the same
  folder in place (image and name change immediately in the grid).
- A Language field (JP/ENG/CN/KR) on both release folders and cards, set via
  a fixed dropdown when creating or editing either.
- Card forms (create and edit) now show category-specific fields driven by
  the card's release category: One Piece gets Kind and Color, Pokémon gets
  Kind and Type, Other gets just ID/Name/Rarity — all from fixed dropdown
  lists instead of free text (an unsorted card with no release falls back to
  the Other field set). `CardCategoryFields` is the shared widget behind all
  three card forms (manual add, post-capture name/tag/file, edit).
- A reusable full-screen image viewer (`openCardImageViewer`) for card
  photos: pinch-to-zoom, swipe between a card's multiple photos with a
  "i / N" position indicator, wired up on the card detail screen's main
  photo/thumbnail strip and the edit-card photo gallery.

### Changed
- My Collection screen is more compact: the large search bar and separate
  Recent/A–Z/Value sort chips are now a single row of three icon buttons
  (Search, Sort, Filter). Search and Filter still open the existing Search
  screen unchanged; Sort opens a bottom sheet with the same three options,
  showing a checkmark on the active one.
- Replaced the camera-only FAB on My Collection with a "+" FAB whose menu
  offers New release folder, Take a photo, and Upload from gallery (the
  latter routes picked photos through the existing batch-triage flow). The
  standalone "+ New release folder" button below the collection grid was
  removed now that it's reachable from the "+" menu.

### Added
- Tap a shot's thumbnail in the burst-capture strip or the batch-triage list
  to open it full-screen with pinch-to-zoom (`PhotoPreviewScreen`), so a shot
  can be checked before committing to it.
- Release folders can have a cover photo: "Set cover photo" in a folder's
  menu offers the camera, the gallery, or any photo already on a card in
  that release, then crops it 4:3 through the new photo editor.
- Cards can be edited after creation (`EditCardScreen`, reached via "Edit" on
  a card's menu): every field (name, number, rarity, condition, copies,
  release/sub-folder, price/date paid, notes, trade/wishlist flags), plus a
  photo gallery — add photos, remove them, and star one to make it the
  thumbnail.
- A card can now hold multiple photos. The photo picker/editor is shared
  (`PhotoEditorScreen`): pinch-zoom and pan a photo under a fixed crop
  frame, rotate it 90° at a time, and recenter, all rasterized into the
  saved file on Save.
- The value chart's Day/Week/Month/Year range now has a second row of count
  options (7d/15d/30d for Day, 4/8/12 buckets for Week/Month/Year, remembered
  per range) and plots real bucketed averages instead of a single window —
  each bucket is the mean of that period's entries, with empty buckets
  rendered as a gap rather than interpolated.
- Dark mode: a Light/Dark/System toggle on the Me tab, persisted across
  restarts, with a matching iOS-dark palette for the whole app.

### Fixed
- Camera preview looked stretched/too wide on the capture screen and on the
  back-of-card quick-shot screen: both put `CameraPreview` inside a
  `Stack(fit: StackFit.expand)` (or, for the quick shot, directly in an
  `Expanded`), which forces tight constraints that override the preview's
  own aspect ratio. Wrapped both in a `Center` + `AspectRatio` matching the
  camera's native ratio instead.
- "Card binned" / "Binned N cards" undo snackbars no longer queue up and stay
  effectively always-visible when binning happens in quick succession
  (folder screen bulk bin, batch-triage single/bulk bin) — each bin now
  clears any pending snackbar before showing its own.
- The card-detail value-range segmented control ("Day/Week/Month/Year") had
  the same selected-checkmark wrapping bug as the Sets screen's sort
  control — "Month" wrapped onto two lines. Same fix: no selected icon.
- APK installed on a physical arm64-v8a phone crashed at startup (ReLinker
  `MissingLibraryException: libflutter.so` — only x86_64 present), and
  persisted after pinning `ndk.abiFilters` in `android/app/build.gradle.kts`
  (still worth keeping — it stops Gradle from ever *excluding* a packaged
  ABI — but it wasn't the actual cause). The real cause: this machine's
  Flutter SDK cache (`bin/cache/artifacts/engine/`) had the `-profile` and
  `-release` Android engine variants for every ABI, but was missing the
  plain **debug** variants (`android-arm`, `android-arm64`, `android-x64`,
  `android-x86`) entirely — so any debug build (`flutter run`, `flutter
  build apk --debug`, Android Studio's Run button) had no arm64 debug
  `libflutter.so` to package in the first place, regardless of Gradle
  config; only release/profile builds happened to work. Fixed by running
  `flutter precache --android` to fetch the missing debug artifacts. No
  repo file changes this time — this was a local-environment gap, not a
  project misconfiguration; documented here in case it recurs after a
  Flutter SDK reinstall or channel switch (check
  `bin/cache/artifacts/engine/android-arm64/` exists before assuming a
  Gradle problem).

### Changed
- Renamed the app (Android launcher label) to "coollexx".
- Replaced the Android launcher icon with the coollexx logo (`applogo/coollex.png`, via `flutter_launcher_icons`).
- Reworked the app theme into a flat, minimalist iOS-style look: iOS system
  blue accent, true neutral grays for surfaces/hairlines, flat cards with a
  hairline border instead of shadows, a pill-shaped tab bar with tinted
  icon/label instead of a Material indicator pill, pill-shaped filter chips
  and segmented controls, and bolder title weights.
- `SetsScreen`'s sort segmented control no longer shows a selected-checkmark
  icon, which was forcing the "Completion" label to wrap onto two lines.

## [1.0.0] - 2026-09-18

Initial commit: Flutter app for cataloguing a Pokémon TCG collection —
camera capture and manual add, releases/sub-folders, trade and wishlist
flags, per-card value history, local SQLite storage.
