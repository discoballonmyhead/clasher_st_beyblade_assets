import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/bridge/engine_bridge.dart';

/// A stand-in engine process: says ready, answers ping.
class _FakeProcess implements Process {
  _FakeProcess() {
    _stdin.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        final req = jsonDecode(line) as Map;
        if (req['cmd'] == 'quit') {
          _exit.complete(0);
          _out.close();
          return;
        }
        _out.add(
          utf8.encode(
            '${jsonEncode({'id': req['id'], 'ok': true, 'result': 'pong'})}\n',
          ),
        );
      },
    );
    scheduleMicrotask(
      () => _out.add(utf8.encode('${jsonEncode({'event': 'ready'})}\n')),
    );
  }

  final _out = StreamController<List<int>>();
  final _stdinCtl = StreamController<List<int>>();
  late final _stdin = _stdinCtl;
  final _exit = Completer<int>();

  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => IOSink(_stdinCtl.sink);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-1);
    return true;
  }
}

void main() {
  test(
    'calls that start the engine at the same time share one process',
    () async {
      var spawned = 0;
      final bridge = EngineBridge(
        spawn: (_) async {
          spawned++;
          await Future<void>.delayed(
            const Duration(milliseconds: 20),
          ); // a slow interpreter start
          return _FakeProcess();
        },
      );
      const cfg = EngineConfig(
        python: 'python3',
        toolsDir: '/tools',
        scriptName: 'translation_tool.py',
      );
      await Future.wait([
        bridge.start(cfg),
        bridge.start(cfg),
        bridge.start(cfg),
      ]);
      expect(spawned, 1);
      expect(await bridge.call('ping'), 'pong');
      await bridge.dispose();
    },
  );
}
