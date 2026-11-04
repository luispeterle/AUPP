import 'dart:io';

import 'package:flutter/material.dart';

const String FontNameDefault = 'Montserrat';

class MaterialThemeInstance {
  static ThemeData? lightTheme;
  static ThemeData? darkTheme;
  static ThemeData? currentTheme;
  static ThemeMode? themeMode;
  static Color defaultSeedColor = Color.fromARGB(255, 255, 214, 91);

  static getDefaultColorScheme(Brightness brightness) {
    ColorScheme defaultColorScheme = ColorScheme.fromSeed(
        seedColor: defaultSeedColor, brightness: brightness);
    return defaultColorScheme;
  }

  /// Always the AUPP yellow, whatever the system's accent colour.
  static Future<ColorScheme> getColorScheme(Brightness brightness) async =>
      getDefaultColorScheme(brightness);

  /// Fork: on the computer the dark theme is a dim gray instead of near black,
  /// easier to read for hours on a large screen. The phone keeps the darker one.
  static ColorScheme liftedDarkScheme(ColorScheme scheme) {
    Color lift(Color color, double amount) =>
        Color.lerp(color, Colors.white, amount)!;
    final base = scheme.surface;
    return scheme.copyWith(
      surface: lift(base, 0.11),
      surfaceDim: lift(base, 0.09),
      surfaceBright: lift(base, 0.24),
      surfaceContainerLowest: lift(base, 0.07),
      surfaceContainerLow: lift(base, 0.14),
      surfaceContainer: lift(base, 0.16),
      surfaceContainerHigh: lift(base, 0.20),
      surfaceContainerHighest: lift(base, 0.25),
      outlineVariant: lift(scheme.outlineVariant, 0.08),
    );
  }

  static bool get _desktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static getMaterialThemeData(Brightness brightness) async {
    var colorScheme = await getColorScheme(brightness);
    if (brightness == Brightness.dark && _desktop) {
      colorScheme = liftedDarkScheme(colorScheme);
    }
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: brightness,
    );
  }

  static Future<ThemeMode> getThemeMode() async {
    // Light or dark as the system says; the colour stays the app's.
    themeMode = ThemeMode.system;
    return themeMode!;
  }

  static Future<ThemeData> getLightTheme() async {
    if (lightTheme == null) {
      lightTheme = await getMaterialThemeData(Brightness.light);
    }
    return lightTheme!;
  }

  static Future<ThemeData> getDarkTheme() async {
    if (darkTheme == null) {
      darkTheme = await getMaterialThemeData(Brightness.dark);
    }
    return darkTheme!;
  }
}
