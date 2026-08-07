import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// App-wide controller for dynamic locale management and dynamic RTL/LTR direction support.
class LocaleController extends ChangeNotifier {
  static const String _boxName = 'settings_box';
  static const String _localeKey = 'app_locale_code';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
  ];

  LocaleController() {
    _loadPersistedLocale();
  }

  /// Initialize controller with persisted locale.
  Future<void> _loadPersistedLocale() async {
    try {
      Box box;
      if (Hive.isBoxOpen(_boxName)) {
        box = Hive.box(_boxName);
      } else {
        box = await Hive.openBox(_boxName);
      }
      final code = box.get(_localeKey, defaultValue: 'en')?.toString() ?? 'en';
      if (code == 'ar' && _locale.languageCode != 'ar') {
        _locale = const Locale('ar');
        notifyListeners();
      } else if (code == 'en' && _locale.languageCode != 'en') {
        _locale = const Locale('en');
        notifyListeners();
      }
    } catch (_) {
      // Safe fallback to default English
    }
  }

  /// Update the locale using a [Locale] object.
  void setLocale(Locale newLocale) {
    if (!supportedLocales.contains(newLocale)) return;
    if (_locale == newLocale) return;

    _locale = newLocale;
    notifyListeners();
    _persistLocale(newLocale.languageCode);
  }

  /// Update the locale using a language code ('en' or 'ar').
  void setLanguageCode(String languageCode) {
    final target = Locale(languageCode.toLowerCase());
    setLocale(target);
  }

  /// Toggle between English and Arabic.
  void toggleLocale() {
    if (_locale.languageCode == 'en') {
      setLocale(const Locale('ar'));
    } else {
      setLocale(const Locale('en'));
    }
  }

  Future<void> _persistLocale(String code) async {
    try {
      Box box;
      if (Hive.isBoxOpen(_boxName)) {
        box = Hive.box(_boxName);
      } else {
        box = await Hive.openBox(_boxName);
      }
      await box.put(_localeKey, code);
    } catch (_) {}
  }
}
