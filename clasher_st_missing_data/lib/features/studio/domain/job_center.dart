import 'dart:async';

import '../../../core/error/failure.dart';
import 'entities/studio_models.dart';
import 'repositories/studio_repository.dart';

/// Follows background jobs. It listens from the start, so lines a job prints before anyone subscribes to its id
/// aren't lost; [run] starts a job and completes with its last event.
class JobCenter {
  JobCenter(this._repo) {
    _sub = _repo.jobEvents.listen(_on);
  }

  final StudioRepository _repo;
  late final StreamSubscription<JobEvent> _sub;
  final _lines = <String, List<String>>{};
  final _done = <String, JobEvent>{};
  final _waiters = <String, List<void Function(JobEvent)>>{};

  /// Ids of jobs started from this app that haven't finished.
  final running = <String>{};

  void _on(JobEvent e) {
    if (e.done) {
      _done[e.id] = e;
      running.remove(e.id);
    } else if (e.line != null) {
      (_lines[e.id] ??= []).add(e.line!);
    }
    for (final w in [...?_waiters[e.id]]) {
      w(e);
    }
  }

  /// Starts a job with [start] and reports each line to [onLine] (earlier ones first) until it ends.
  Future<Result<JobEvent>> run(Future<Result<String>> Function() start, void Function(String line) onLine) async {
    final started = await start();
    switch (started) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final id):
        running.add(id);
        final done = Completer<JobEvent>();
        var seen = 0;
        void feed(JobEvent e) {
          final lines = _lines[id] ?? const [];
          while (seen < lines.length) {
            onLine(lines[seen++]);
          }
          if (e.done && !done.isCompleted) done.complete(e);
        }

        (_waiters[id] ??= []).add(feed);
        feed(_done[id] ?? JobEvent(id: id)); // what arrived before we listened
        final end = await done.future;
        _waiters.remove(id);
        _lines.remove(id);
        _done.remove(id);
        return Ok(end);
    }
  }

  Future<void> stop(String id) => _repo.stopJob(id);

  Future<void> dispose() => _sub.cancel();
}
