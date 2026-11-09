import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/settings/app_settings.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.python,
    required this.toolsDir,
    required this.publishing,
    this.testing = false,
    this.result,
    this.ok,
    this.message,
  });

  final String python;
  final String toolsDir;
  final PublishingConstants publishing;
  final bool testing;
  final String? result;
  final bool? ok;
  final String? message;

  SettingsState copyWith({
    String? python,
    String? toolsDir,
    PublishingConstants? publishing,
    bool? testing,
    String? result,
    bool? ok,
    String? message,
  }) => SettingsState(
    python: python ?? this.python,
    toolsDir: toolsDir ?? this.toolsDir,
    publishing: publishing ?? this.publishing,
    testing: testing ?? this.testing,
    result: result,
    ok: ok,
    message: message,
  );

  @override
  List<Object?> get props => [
    python,
    toolsDir,
    publishing,
    testing,
    result,
    ok,
    message,
  ];
}

/// Python + tools folder (with a test that starts both engines), the publishing constants, and a settings
/// backup file.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._bridge, {EngineBridge? translationBridge})
    : _translations = translationBridge,
      super(
        SettingsState(
          python: _settings.python,
          toolsDir: _settings.toolsDir,
          publishing: _settings.publishing,
        ),
      );

  final AppSettings _settings;
  final EngineBridge _bridge;
  final EngineBridge? _translations;

  void setPython(String v) => emit(state.copyWith(python: v));
  void setToolsDir(String v) => emit(state.copyWith(toolsDir: v));

  Future<void> saveAndTest() async {
    _settings
      ..python = state.python.trim()
      ..toolsDir = state.toolsDir.trim();
    emit(state.copyWith(testing: true));
    final lines = <String>[];
    var ok = true;
    for (final (name, bridge, config) in [
      ('Data engine', _bridge, _settings.engineConfig),
      if (_translations != null)
        (
          'Translation engine',
          _translations,
          _settings.translationEngineConfig,
        ),
    ]) {
      try {
        await bridge.stop();
        await bridge.start(config);
        final pong = await bridge.call('ping');
        lines.add('$name running ($pong)');
      } on EngineException catch (e) {
        ok = false;
        lines.add('$name: ${e.message}');
      }
    }
    emit(state.copyWith(testing: false, ok: ok, result: lines.join('\n')));
  }

  void editPublishing(
    PublishingConstants Function(PublishingConstants p) change,
  ) => emit(state.copyWith(publishing: change(state.publishing)));

  Future<void> savePublishing() async {
    await _settings.setPublishing(state.publishing);
    emit(state.copyWith(message: 'Publishing settings saved'));
  }

  /// Writes every setting to `folder/clasher_studio_settings-DATE.json` -> the file.
  Future<String> exportTo(String folder) async {
    final now = DateTime.now();
    final name =
        'clasher_studio_settings-${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.json';
    final f = File('$folder${Platform.pathSeparator}$name');
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_settings.exportAll()),
    );
    emit(state.copyWith(message: 'Settings written to ${f.path}'));
    return f.path;
  }

  Future<void> importFrom(String file) async {
    try {
      final data = Map<String, Object?>.from(
        jsonDecode(await File(file).readAsString()) as Map,
      );
      final n = await _settings.importAll(data);
      emit(
        SettingsState(
          python: _settings.python,
          toolsDir: _settings.toolsDir,
          publishing: _settings.publishing,
          message:
              'Restored $n setting(s) - restart the Studio to apply them everywhere',
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(message: 'Couldn\'t read that file: $e'));
    }
  }
}
