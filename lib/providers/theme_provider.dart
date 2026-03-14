import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AppColors and AppTheme have been moved to lib/theme/app_theme.dart.
// Re-exported here so existing imports of theme_provider.dart keep working.
export '../theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

class ThemeProvider extends ChangeNotifier {
  static const _key = 'dark_mode';
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get themeMode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_key) ?? true;
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
    notifyListeners();
  }
}
