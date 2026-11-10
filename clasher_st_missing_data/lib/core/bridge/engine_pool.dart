import 'dart:async';

import 'engine_bridge.dart';

/// One data engine per open workbook. Switching workbooks switches engines, so each keeps its unsaved edits in
/// memory (and its own recovery journal) until it's saved or closed.
class WorkbookEngines {
  WorkbookEngines({EngineBridge Function()? create}) : _create = create ?? EngineBridge.new;

  final EngineBridge Function() _create;
  final _byPath = <String, EngineBridge>{};
  final _subs = <String, StreamSubscription<Map<String, dynamic>>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  EngineBridge? _scratch; // before any workbook is open (ping, settings test)
  String? _current;

  static String key(String path) => path.replaceAll('\\', '/');

  String? get current => _current;
  List<String> get paths => [..._byPath.keys];
  bool isOpen(String path) => _byPath.containsKey(key(path));

  /// The engine of the current workbook.
  EngineBridge get bridge => _current != null ? _byPath[_current]! : (_scratch ??= _watch('', _create()));

  /// Log lines and events of every engine.
  Stream<Map<String, dynamic>> get events => _events.stream;

  EngineBridge _watch(String path, EngineBridge b) {
    _subs[path] = b.events.listen(_events.add);
    return b;
  }

  /// Makes [path] the current workbook -> true when its engine is new (the workbook still has to be opened).
  bool activate(String path) {
    final k = key(path);
    _current = k;
    if (_byPath.containsKey(k)) return false;
    _byPath[k] = _watch(k, _create());
    return true;
  }

  /// Stops the workbook's engine (unsaved edits stay in its recovery journal).
  Future<void> close(String path) async {
    final k = key(path);
    final b = _byPath.remove(k);
    await _subs.remove(k)?.cancel();
    if (_current == k) _current = _byPath.keys.lastOrNull;
    await b?.dispose();
  }

  Future<void> dispose() async {
    for (final p in paths) {
      await close(p);
    }
    await _subs.remove('')?.cancel();
    await _scratch?.dispose();
    await _events.close();
  }
}
