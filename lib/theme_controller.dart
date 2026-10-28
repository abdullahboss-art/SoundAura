import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App ka theme (Dark / Light). Chunav phone me save rehta hai.
class AppThemeController {
  AppThemeController._();

  static const String _key = 'pref_theme_mode';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isDark => themeMode.value != ThemeMode.light;

  /// App shuru hote hi (runApp se pehle) ek baar call karo.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'light') themeMode.value = ThemeMode.light;
    } catch (_) {}
  }

  static void setDark() => _apply(ThemeMode.dark);
  static void setLight() => _apply(ThemeMode.light);

  static void toggle() => _apply(isDark ? ThemeMode.light : ThemeMode.dark);

  static void _apply(ThemeMode mode) {
    if (themeMode.value == mode) return;
    themeMode.value = mode;
    _save(mode);
    _rebuildAll();
  }

  static Future<void> _save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }

  /// Saari screens ko ek baar dobara banata hai, taake naye rang foran lag jayein.
  /// (Navigation aur gaana chalta rehta hai, kuch reset nahi hota.)
  static void _rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;

    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
}