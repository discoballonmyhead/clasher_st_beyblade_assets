import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Thrown when the engine answers `ok: false` or can't be reached.
class EngineException implements Exception {
  const EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where a Python engine lives. [toolsDir] is the folder with the engine scripts
/// (the clasher_st_beyblade_assets repo); [python] the interpreter to run it with;
/// [scriptName] which engine: missing_data_tool.py (data) or translation_tool.py.
class EngineConfig {
  const EngineConfig({
    required this.python,
    required this.toolsDir,
    this.scriptName = 'missing_data_tool.py',
  });

  final String python;
  final String toolsDir;
  final String scriptName;

  String get script => '$toolsDir${Platform.pathSeparator}$scriptName';

  bool sameAs(EngineConfig? o) =>
      o != null &&
      o.python == python &&
      o.toolsDir == toolsDir &&
      o.scriptName == scriptName;
}

/// Talks to `missing_data_tool.py serve`: one long-running process that keeps the workbook
/// in memory. Requests and responses are JSON lines matched by id; events (log lines) arrive
/// on [events]. Only this class knows the engine is Python - swap it for another data source
/// (e.g. Supabase) without touching the domain or the UI.
class EngineBridge {
  EngineBridge({Future<Process> Function(EngineConfig config)? spawn})
    : _spawn = spawn ?? _defaultSpawn;

  final Future<Process> Function(EngineConfig config) _spawn;
  Process? _process;
  EngineConfig? _config;
  int _nextId = 0;
  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Completer<void>? _ready;
  // stdin accepts one flush at a time; cubits often call together, so writes queue here.
  Future<void> _writes = Future.value();

  /// Log lines and other events from the engine.
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get isRunning => _process != null;

  static Future<Process> _defaultSpawn(EngineConfig c) => Process.start(
    c.python,
    [c.script, 'serve'],
    workingDirectory: c.toolsDir,
    environment: {'PYTHONIOENCODING': 'utf-8', 'PYTHONUNBUFFERED': '1'},
  );

  Future<void>? _starting;

  /// Starts the engine (or restarts it with a new config). Calls that arrive while it is starting share that
  /// start: two cubits asking at once must not spawn two engines (the first caller would wait on a "ready" that
  /// went to the second).
  Future<void> start(EngineConfig config) {
    if (config.sameAs(_config) && (_process != null || _starting != null)) {
      return _starting ?? _ready?.future ?? Future.value();
    }
    _config = config; // before the first await, so a concurrent caller sees this start
    final f = _start(config);
    _starting = f;
    f.then((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_starting, f)) _starting = null;
    });
    return f;
  }

  Future<void> _start(EngineConfig config) async {
    await stop();
    _config = config;
    final ready = _ready = Completer<void>();
    final Process p;
    try {
      p = await _spawn(config);
    } on ProcessException catch (e) {
      throw EngineException(
        'Could not start "${config.python}": ${e.message}. '
        'Check the Python path in Settings.',
      );
    }
    _process = p;
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: () => _onExit('The engine stopped.'));
    final stderr = StringBuffer();
    p.stderr.transform(utf8.decoder).listen((s) {
      stderr.write(s);
      _events.add({'event': 'stderr', 'message': s.trimRight()});
    });
    unawaited(
      p.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            EngineException(
              'The engine exited ($code) before it was ready.\n${stderr.toString().trim()}',
            ),
          );
        }
        _onExit('The engine exited with code $code.');
      }),
    );
    return ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw const EngineException('The engine did not start within 30 s.'),
    );
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _events.add({'event': 'stdout', 'message': line});
      return;
    }
    if (msg['event'] == 'ready') {
      if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      return;
    }
    final id = msg['id'];
    if (id is int && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      if (msg['ok'] == true) {
        c.complete(msg['result']);
      } else {
        c.completeError(
          EngineException('${msg['error'] ?? 'Unknown engine error'}'),
        );
      }
      return;
    }
    _events.add(msg);
  }

  void _onExit(String why) {
    _process = null;
    _writes = Future.value();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(EngineException(why));
    }
    _pending.clear();
  }

  /// Sends one command and waits for its answer. [timeout] null = wait as long as it takes
  /// (wiki fills); everything else answers in well under a minute.
  Future<Object?> call(
    String cmd, [
    Map<String, Object?> args = const {},
    Duration? timeout = const Duration(minutes: 2),
  ]) async {
    final p = _process;
    if (p == null) {
      throw const EngineException('The engine is not running. Check Settings.');
    }
    final id = ++_nextId;
    final c = Completer<Object?>();
    _pending[id] = c;
    final line = jsonEncode({'id': id, 'cmd': cmd, 'args': args});
    final write = _writes.then((_) {
      p.stdin.writeln(line);
      return p.stdin.flush();
    });
    _writes = write.catchError((_) {});
    try {
      await write;
    } catch (e) {
      _pending.remove(id);
      throw EngineException('Could not send "$cmd" to the engine: $e');
    }
    final f = c.future;
    return timeout == null
        ? f
        : f.timeout(
            timeout,
            onTimeout: () {
              _pending.remove(id);
              throw EngineException(
                '"$cmd" took longer than ${timeout.inSeconds}s.',
              );
            },
          );
  }

  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    try {
      await _writes;
      p.stdin.writeln(jsonEncode({'id': 0, 'cmd': 'quit'}));
      await p.stdin.flush();
      await p.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      p.kill();
    }
    _process = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
