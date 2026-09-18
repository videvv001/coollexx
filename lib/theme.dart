import 'package:flutter/material.dart';

/// Accent taken from the wireframe's Industry design-system tokens
/// (`_ds/industry-*/styles.css`). Wireframe pixel values (9-11px type,
/// square corners) were explicitly called out as not-for-shipping — this
/// theme uses Material 3 defaults for type scale, spacing and shape, with
/// the accent hue as the seed color.
const _accentSeed = Color(0xFF5980A6);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _accentSeed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surface),
    // A bounded minimum size, not Size.fromHeight(48) — that sets width to
    // infinity, which is fine for a button alone in a Column but crashes
    // the moment one ends up inline in a Row without its own Expanded/
    // SizedBox. Screens that want a full-width primary button wrap it in
    // SizedBox(width: double.infinity, ...) explicitly instead.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
