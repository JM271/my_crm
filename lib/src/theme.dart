import 'package:flutter/material.dart';

const forest = Color(0xFF214E3D);
const forestDark = Color(0xFF163A2D);
const sage = Color(0xFFE7F0E9);
const ink = Color(0xFF202923);
const muted = Color(0xFF7C8780);
const line = Color(0xFFEAEEEB);
const canvas = Color(0xFFF6F8F5);
const danger = Color(0xFFB4483C);

/// Soft avatar palettes (background, foreground), picked by name hash.
const avatarPalettes = <(Color, Color)>[
  (Color(0xFFE8EEDD), forest),
  (Color(0xFFF4E7DC), Color(0xFF9B6034)),
  (Color(0xFFE6EAF3), Color(0xFF52638F)),
  (Color(0xFFF1E8F0), Color(0xFF8A6281)),
  (Color(0xFFE9EFF2), Color(0xFF557481)),
  (Color(0xFFF3EFDD), Color(0xFF7D6B2E)),
];

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: forest,
      primary: forest,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Arial',
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: ink),
      bodySmall: TextStyle(color: muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: forest,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
