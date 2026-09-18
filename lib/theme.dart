import 'package:flutter/material.dart';

/// iOS system blue — the accent seed (brighter in dark mode, matching
/// Apple's own light/dark blue pair).
const _accentSeedLight = Color(0xFF007AFF);
const _accentSeedDark = Color(0xFF0A84FF);

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accentSeed = dark ? _accentSeedDark : _accentSeedLight;

  // fromSeed derives every container/on-color pair with guaranteed
  // contrast via Material Color Utilities; only the roles that need to
  // read as true iOS neutrals (surfaces, hairlines, secondary text) are
  // overridden — tonalSpot's tint on those looked purple-gray, not iOS
  // gray, in either brightness.
  final scheme =
      ColorScheme.fromSeed(seedColor: accentSeed, brightness: brightness)
          .copyWith(
            surface: dark ? Colors.black : Colors.white,
            onSurface: dark
                ? const Color(0xFFF2F2F7)
                : const Color(0xFF1C1C1E),
            onSurfaceVariant: const Color(0xFF8E8E93), // iOS systemGray, same in both
            surfaceContainerHighest: dark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFFF2F2F7),
            outline: dark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
            outlineVariant: dark
                ? const Color(0xFF38383A)
                : const Color(0xFFE5E5EA),
            primary: accentSeed,
            onPrimary: Colors.white,
            primaryContainer: dark
                ? const Color(0xFF0A2A4D)
                : const Color(0xFFE5F1FF),
            onPrimaryContainer: dark
                ? const Color(0xFFAFD4FF)
                : const Color(0xFF00408A),
          );
  const hairlineWidth = 1.0;
  final radius14 = BorderRadius.circular(14);
  // This project ships Android-only (no ios/ folder), so there's no device
  // where a ".SF Pro Text" fontFamily hack would actually resolve to the
  // system font — it would only add an unpredictable fallback-font risk on
  // Android for no benefit. Flutter's bundled default already reads as a
  // clean modern sans; only the weight scale changes here.
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .copyWith(
        titleLarge: const TextStyle(fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600),
        titleSmall: const TextStyle(fontWeight: FontWeight.w600),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 0.5,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 60,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius14,
        side: BorderSide(color: scheme.outlineVariant, width: hairlineWidth),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: radius14),
      iconColor: scheme.onSurfaceVariant,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 1,
      focusElevation: 1,
      hoverElevation: 2,
      highlightElevation: 2,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const CircleBorder(),
    ),
    // A bounded minimum size, not Size.fromHeight(48) — that sets width to
    // infinity, which is fine for a button alone in a Column but crashes
    // the moment one ends up inline in a Row without its own Expanded/
    // SizedBox. Screens that want a full-width primary button wrap it in
    // SizedBox(width: double.infinity, ...) explicitly instead.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: radius14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: scheme.primary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: radius14,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurfaceVariant,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
