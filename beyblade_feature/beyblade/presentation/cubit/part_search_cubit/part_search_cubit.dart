import 'dart:developer' as dev;

import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

part 'part_search_state.dart';

/// Wraps [SearchBeybladePartsUseCase] with debounce-safe state — the same
/// cubit this page uses is meant to back the bey-builder's part pickers
/// later too, since it's the one shared search per the original spec.
class PartSearchCubit extends Cubit<PartSearchState> {
  PartSearchCubit(this._search) : super(const PartSearchEmpty());

  final SearchBeybladePartsUseCase _search;

  static const _logName = 'Beyblade.PartSearch';

  /// Bumped on every call so a slow, now-superseded query can't overwrite
  /// a faster, more recent one when both resolve out of order.
  int _seq = 0;

  String _lastQuery = '';

  Future<void> query(String q) async {
    _lastQuery = q;
    final mySeq = ++_seq;
    final trimmed = q.trim();

    dev.log('query (#$mySeq) requested: "$trimmed"', name: _logName);

    if (trimmed.isEmpty) {
      dev.log('query (#$mySeq) is empty, emitting PartSearchEmpty',
          name: _logName);
      emit(const PartSearchEmpty());
      return;
    }

    emit(const PartSearchLoading());
    final stopWatch = Stopwatch()..start();

    try {
      final results = await _search(trimmed);
      stopWatch.stop();

      if (mySeq != _seq) {
        dev.log(
            'query (#$mySeq) superseded by newer query (#$_seq). Discarding ${results.length} results.',
            name: _logName);
        return;
      }

      dev.log(
          'query (#$mySeq) returned ${results.length} results in ${stopWatch.elapsedMilliseconds}ms',
          name: _logName);
      emit(PartSearchResults(results));
    } catch (e, st) {
      stopWatch.stop();

      if (mySeq != _seq) {
        dev.log(
            'query (#$mySeq) failed, but was superseded by (#$_seq). Discarding error.',
            name: _logName);
        return;
      }

      dev.log('query (#$mySeq) failed in ${stopWatch.elapsedMilliseconds}ms',
          name: _logName, error: e, stackTrace: st, level: 1000);
      emit(PartSearchError(e.toString()));
    }
  }

  /// Re-runs whatever was last searched — used by pull-to-refresh, e.g.
  /// right after downloading new/updated data, to see current results
  /// without retyping.
  Future<void> refresh() {
    dev.log('refresh triggered with last query: "$_lastQuery"', name: _logName);
    return query(_lastQuery);
  }
}
