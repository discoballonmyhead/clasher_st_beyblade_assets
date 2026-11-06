import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../domain/usecases/fill_usecases.dart';
import 'wiki_state.dart';

/// Re-reads rows' wiki pages through the scraper (one request at a time - safe for the IP) and
/// shows its log live. Fills blank cells only.
class WikiCubit extends Cubit<WikiState> {
  WikiCubit({required FillFromWiki fill, required DataChangeNotifier changes})
      : _fill = fill,
        _changes = changes,
        super(const WikiState()) {
    _sub = _fill.log.listen(_addLine);
  }

  final FillFromWiki _fill;
  final DataChangeNotifier _changes;
  late final StreamSubscription<String> _sub;

  void _addLine(String line) {
    if (isClosed) return;
    final lines = [...state.lines, ...line.split('\n').where((l) => l.trim().isNotEmpty)];
    emit(state.copyWith(lines: lines.length > 400 ? lines.sublist(lines.length - 400) : lines));
  }

  Future<void> start(String sheet, List<String> ids) async {
    if (state.running || ids.isEmpty) return;
    emit(state.copyWith(running: true));
    _addLine('Wiki fill: ${ids.length} row(s) of $sheet ...');
    final res = await _fill(sheet, ids);
    if (isClosed) return;
    res.fold(
      (f) => emit(state.copyWith(running: false, error: f.message)),
      (pages) => emit(state.copyWith(running: false, message: 'Wiki fill done: $pages page(s) re-read')),
    );
    _changes.notify(DataChange.wikiFinished);
  }

  Future<void> stop() async {
    await _fill.stop();
    _addLine('Stopping after the current request ...');
  }

  void clearLog() => emit(state.copyWith(lines: const []));

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
