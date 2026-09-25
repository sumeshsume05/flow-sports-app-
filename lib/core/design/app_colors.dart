import 'package:flutter/material.dart';

/// Brand palette — a "sport-energy" look: a vivid orange primary for actions
/// and live emphasis, an electric blue secondary, and a magenta tertiary used
/// to tell the boys/girls categories apart at a glance. Built from Material
/// 3's seed algorithm (guarantees accessible contrast across every
/// surface/container role) with the brand hues pinned explicitly on top,
/// rather than leaving everything to the seed to guess.
class AppColors {
  AppColors._();

  static const orange = Color(0xFFFF5A1F);
  static const blue = Color(0xFF00B4D8);
  static const pink = Color(0xFFEF2D8C);

  static const liveRed = Color(0xFFE5322D);
  static const winGreen = Color(0xFF1FAE5C);
  static const warningAmber = Color(0xFFF5A623);

  static final ColorScheme light = ColorScheme.fromSeed(
    seedColor: orange,
    brightness: Brightness.light,
  ).copyWith(
    primary: orange,
    secondary: blue,
    tertiary: pink,
    error: liveRed,
  );

  static final ColorScheme dark = ColorScheme.fromSeed(
    seedColor: orange,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFFF8A5C),
    secondary: const Color(0xFF5CE1F2),
    tertiary: const Color(0xFFFF6FB8),
    error: const Color(0xFFFF6B66),
  );

  // Semantic status colors, same across both themes — the single source of
  // truth for LIVE/win/tie coloring, replacing ad-hoc Colors.red/green/amber
  // scattered across screens.
  static const live = liveRed;
  static const win = winGreen;
  static const warning = warningAmber;

  // Category accents — Boys uses the secondary blue, Girls the tertiary pink.
  static const boysAccent = blue;
  static const girlsAccent = pink;
}
