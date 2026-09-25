import 'package:flutter/material.dart';

/// The app's type scale, built on the system font (Roboto on Android) —
/// deliberately not a `google_fonts` download. `google_fonts` fetches font
/// files over the network on first use; this app is used courtside on poor
/// connections, so every bit of UI chrome — including text — must render
/// instantly with zero network dependency.
TextTheme buildAppTextTheme(ColorScheme scheme) {
  final onSurface = scheme.onSurface;
  final onSurfaceMuted = scheme.onSurfaceVariant;

  return TextTheme(
    displayLarge: TextStyle(
        fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: onSurface),
    displayMedium: TextStyle(
        fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: onSurface),
    headlineLarge: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: onSurface),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: onSurface),
    headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: onSurface),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurfaceMuted),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: onSurfaceMuted),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onSurfaceMuted),
    labelSmall: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: onSurfaceMuted),
  );
}
