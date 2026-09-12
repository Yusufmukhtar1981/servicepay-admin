import 'package:flutter/material.dart';

/// Shared themes for the production admin portal.
///
/// Keeping the color schemes here makes admin screens use readable foreground
/// colors in both light and dark mode without changing their navigation or
/// authorization behavior.
class AdminTheme {
  const AdminTheme._();

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    );
  }

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF73D3BF),
      brightness: Brightness.dark,
      surface: const Color(0xFF102D3A),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B2029),
    );
  }
}
