import 'package:flutter/material.dart';

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
