import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/settings/app_settings.dart';

class SettingsState extends Equatable {
  const SettingsState({required this.python, required this.toolsDir, this.testing = false, this.result, this.ok});

  final String python;
  final String toolsDir;
  final bool testing;
  final String? result;
  final bool? ok;

  SettingsState copyWith({String? python, String? toolsDir, bool? testing, String? result, bool? ok}) => SettingsState(
        python: python ?? this.python,
        toolsDir: toolsDir ?? this.toolsDir,
        testing: testing ?? this.testing,
        result: result,
        ok: ok,
      );

  @override
  List<Object?> get props => [python, toolsDir, testing, result, ok];
}

/// Python interpreter + tools folder, with a "test connection" that starts the engine.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._bridge)
      : super(SettingsState(python: _settings.python, toolsDir: _settings.toolsDir));

  final AppSettings _settings;
  final EngineBridge _bridge;

  void setPython(String v) => emit(state.copyWith(python: v));
  void setToolsDir(String v) => emit(state.copyWith(toolsDir: v));

  Future<void> saveAndTest() async {
    _settings
      ..python = state.python.trim()
      ..toolsDir = state.toolsDir.trim();
    emit(state.copyWith(testing: true));
    try {
      await _bridge.stop();
      await _bridge.start(_settings.engineConfig);
      final pong = await _bridge.call('ping');
      emit(state.copyWith(testing: false, ok: true, result: 'Engine running ($pong)'));
    } on EngineException catch (e) {
      emit(state.copyWith(testing: false, ok: false, result: e.message));
    }
  }
}
