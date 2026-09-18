# Changelog

All notable changes to this project are documented here, newest first.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
