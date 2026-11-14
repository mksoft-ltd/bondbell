import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bondbell's own look: bottle green and brass on warm paper. Deliberately
/// unlike NS&I's branding. Type runs a step larger than Material's defaults
/// because the audience skews older; everything still honours the user's
/// text-size setting.
abstract final class AppTheme {
  static const Color green = Color(0xFF1F5C45);
  static const Color greenDark = Color(0xFF8FD3B4);
  static const Color brass = Color(0xFF9A6B12);
  static const Color brassLight = Color(0xFFE2B85C);
  static const Color paper = Color(0xFFFAF7F0);
  static const Color ink = Color(0xFF1B1F1C);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.light,
    ).copyWith(
      primary: green,
      onPrimary: Colors.white,
      secondary: brass,
      onSecondary: Colors.white,
      tertiary: brass,
      surface: paper,
      onSurface: ink,
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.dark,
    ).copyWith(
      primary: greenDark,
      onPrimary: const Color(0xFF00382A),
      secondary: brassLight,
      onSecondary: const Color(0xFF3D2A00),
      tertiary: brassLight,
      surface: const Color(0xFF121614),
      onSurface: const Color(0xFFE6E9E6),
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final bool dark = scheme.brightness == Brightness.dark;
    final TextTheme base = ThemeData(brightness: scheme.brightness).textTheme;
    final TextTheme text = base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          // Material's body tracking (0.5 / 0.25 / 0.4) is tuned for 14–16pt;
          // at these larger sizes it reads as gappy, so it is tightened.
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 18,
            height: 1.4,
            letterSpacing: 0.15,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 16,
            height: 1.4,
            letterSpacing: 0.1,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 14,
            height: 1.35,
            letterSpacing: 0.2,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        // No titleTextStyle here: `text` has no font sizes yet (Material's
        // geometry is merged in later by Theme), so a theme-level style came
        // out at 14pt. The AppBar default (textTheme.titleLarge, 22pt w700)
        // also keeps every AppBar's foregroundColor working.
        // Icon brightness only; bar colours are the deprecated Android 15
        // APIs Play warns about.
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1B201D) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: dark ? const Color(0xFF1B201D) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF181C1A) : Colors.white,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          text.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
