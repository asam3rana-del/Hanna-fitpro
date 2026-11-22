import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hanna Fitness ka premium palette: matte black + champagne gold. Dark mode default hai.
@immutable
class AppPalette {
  final Color bg; // screen background
  final Color card; // cards / sheets
  final Color cardAlt; // thora alag card (list rows, chips)
  final Color header; // hero header (gradient ka pehla rang)
  final Color header2; // hero header (gradient ka doosra rang)
  final Color gold; // main accent
  final Color goldDark;
  final Color goldSoft; // gold ka halka background (chips, badges)
  final Color ink; // main text
  final Color muted; // secondary text
  final Color border;
  final Color field; // text field fill
  final Color green, greenSoft, red, redSoft, amber, amberSoft, blue, blueSoft, purple, purpleSoft;
  final bool isDark;

  const AppPalette({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.header,
    required this.header2,
    required this.gold,
    required this.goldDark,
    required this.goldSoft,
    required this.ink,
    required this.muted,
    required this.border,
    required this.field,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.amber,
    required this.amberSoft,
    required this.blue,
    required this.blueSoft,
    required this.purple,
    required this.purpleSoft,
    required this.isDark,
  });

  /// Header / gold buttons par likha text.
  Color get onHeader => const Color(0xFFF7F3E8);
  Color get onGold => const Color(0xFF14120C);
}

class ThemeManager {
  ThemeManager._();

  static const _keyDarkMode = 'dark_mode';

  static const light = AppPalette(
    bg: Color(0xFFF5F2EA),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFFAF7F0),
    header: Color(0xFF15151A),
    header2: Color(0xFF2A2720),
    gold: Color(0xFFB8912B),
    goldDark: Color(0xFF8F6F1C),
    goldSoft: Color(0xFFF4EBD3),
    ink: Color(0xFF17161A),
    muted: Color(0xFF6F6A5F),
    border: Color(0xFFE6DFCF),
    field: Color(0xFFF8F5EE),
    green: Color(0xFF16804B),
    greenSoft: Color(0xFFDDF3E6),
    red: Color(0xFFC6363C),
    redSoft: Color(0xFFFBE3E3),
    amber: Color(0xFFB86E00),
    amberSoft: Color(0xFFFFEFD6),
    blue: Color(0xFF2563EB),
    blueSoft: Color(0xFFE1EAFD),
    purple: Color(0xFF7C3AED),
    purpleSoft: Color(0xFFEDE5FD),
    isDark: false,
  );

  static const dark = AppPalette(
    bg: Color(0xFF0C0C0F),
    card: Color(0xFF17171C),
    cardAlt: Color(0xFF1E1E24),
    header: Color(0xFF1B1A1F),
    header2: Color(0xFF2B2619),
    gold: Color(0xFFD9B45A),
    goldDark: Color(0xFFB8912B),
    goldSoft: Color(0xFF332B17),
    ink: Color(0xFFF3EFE4),
    muted: Color(0xFF9D978A),
    border: Color(0xFF2A2930),
    field: Color(0xFF1E1E24),
    green: Color(0xFF4ADE80),
    greenSoft: Color(0xFF143222),
    red: Color(0xFFF87171),
    redSoft: Color(0xFF3A1717),
    amber: Color(0xFFFBBF24),
    amberSoft: Color(0xFF3A2C0E),
    blue: Color(0xFF7AA7FF),
    blueSoft: Color(0xFF16233F),
    purple: Color(0xFFB794F6),
    purpleSoft: Color(0xFF2A1F44),
    isDark: true,
  );

  /// MaterialApp is par listen karta hai — toggle par poori app dobara banti hai.
  static final ValueNotifier<bool> isDark = ValueNotifier<bool>(true);

  static AppPalette get palette => isDark.value ? dark : light;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    isDark.value = p.getBool(_keyDarkMode) ?? true;
  }

  static Future<void> setDarkMode(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyDarkMode, enabled);
    isDark.value = enabled;
  }

  /// Poori app ka ThemeData (sirf stable fields — naye Flutter versions mein bhi compile ho).
  static ThemeData buildTheme() {
    final p = palette;
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: p.gold, brightness: brightness).copyWith(
      primary: p.gold,
      onPrimary: p.onGold,
      secondary: p.goldDark,
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.card,
      surfaceContainerLow: p.card,
      surfaceContainer: p.card,
      surfaceContainerHigh: p.card,
      surfaceContainerHighest: p.field,
      outline: p.muted,
      outlineVariant: p.border,
      error: p.red,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.card,
      dividerColor: p.border,
      fontFamily: 'Roboto',
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.gold,
          foregroundColor: p.onGold,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? const Color(0xFF2A2930) : const Color(0xFF1B1A1F),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
    return base.copyWith(textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink));
  }

  /// Har text field ki premium decoration (component theme ki jagah — naye Flutter mein class naam badalte rehte hain).
  static InputDecoration field(String label, {IconData? icon, String? hint, Widget? suffix, String? prefixText}) {
    final p = palette;
    OutlineInputBorder b(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      prefixIcon: icon == null ? null : Icon(icon, color: p.gold, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: p.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.muted),
      border: b(p.border),
      enabledBorder: b(p.border),
      focusedBorder: b(p.gold, 1.6),
      errorBorder: b(p.red),
      focusedErrorBorder: b(p.red, 1.6),
    );
  }
}
