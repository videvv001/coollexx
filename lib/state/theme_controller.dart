import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'theme_mode';

/// Persists the user's Light/Dark/System choice across restarts. Loads
/// asynchronously (`SharedPreferences` has no sync API), so `mode` starts
/// at `ThemeMode.system` until `_load()` resolves — a one-frame default
/// that's already correct for most users, so no loading gate is needed.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _load();
  }

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    _mode = ThemeMode.values.byName(saved);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
