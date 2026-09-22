import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'ocr_autofill_enabled';

/// Whether card scans should run on-device OCR to suggest name/ID/language.
/// Off by default for nobody — defaults to on, since that's the whole
/// point of scanning — but collectors of unsupported games can turn it off
/// so the category prompt (see `category_prompt.dart`) stops asking.
/// Same load/persist shape as `ThemeController`.
class OcrSettings extends ChangeNotifier {
  OcrSettings() {
    _load();
  }

  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey);
    if (saved == null) return;
    _enabled = saved;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}
