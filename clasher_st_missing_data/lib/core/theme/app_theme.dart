import 'package:flutter/material.dart';

/// A real monospace font on each OS. ('monospace' alone can resolve to a CJK font that draws \ as a yen sign.)
const monoFamily = 'Consolas';
const monoFallback = ['Menlo', 'SF Mono', 'DejaVu Sans Mono', 'Liberation Mono', 'Noto Sans Mono', 'Courier New', 'monospace'];

abstract final class AppTheme {
  static const _seed = Color(0xFF2F6FED);

  /// Highlight for empty fields.
  static const missing = Color(0xFFFFE9C7);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: _seed));
  static ThemeData dark() => _base(ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark));

  static ThemeData _base(ColorScheme cs) => ThemeData(
        colorScheme: cs,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(isDense: true, border: OutlineInputBorder()),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
        listTileTheme: const ListTileThemeData(dense: true),
      );
}
