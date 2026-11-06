import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:missing_data_app/core/services/data_change_notifier.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row_lifecycle.dart';
import 'package:missing_data_app/features/missing_data/domain/usecases/row_lifecycle_usecases.dart';

class IdCheckState extends Equatable {
  const IdCheckState({
    this.pending = const [],
    this.busy = false,
    this.message,
    this.error,
  });

  /// Tabs to ask about (not answered "not now" since their ids last changed).
  final List<IdIssue> pending;
  final bool busy;
  final String? message;
  final String? error;

  @override
  List<Object?> get props => [pending, busy, message, error];
}

/// Watches that ids run 1..N in every tab. After the workbook opens and after rows are added, deleted or
/// restored it checks again; the page asks about each tab in [IdCheckState.pending].
class IdCheckCubit extends Cubit<IdCheckState> {
  IdCheckCubit({
    required CheckIds check,
    required RenumberIds renumber,
    required DataChangeNotifier changes,
  }) : _check = check,
       _renumber = renumber,
       _changes = changes,
       super(const IdCheckState()) {
    _sub = changes.stream.listen((c) {
      if (c == DataChange.workbookOpened) {
        _snoozed.clear();
        emit(const IdCheckState());
      }
    });
  }

  final CheckIds _check;
  final RenumberIds _renumber;
  final DataChangeNotifier _changes;
  final _snoozed = <String>{};
  late final StreamSubscription<DataChange> _sub;

  static String _key(IdIssue i) => '${i.sheet}|${i.fingerprint}';

  Future<void> check() async {
    final res = await _check();
    res.fold(
      (f) => emit(IdCheckState(error: f.message)),
      (issues) => emit(
        IdCheckState(
          pending: [
            for (final i in issues)
              if (!_snoozed.contains(_key(i))) i,
          ],
        ),
      ),
    );
  }

  /// "Not now": don't ask about this tab again until its ids change.
  void snooze(IdIssue issue) {
    _snoozed.add(_key(issue));
    emit(
      IdCheckState(
        pending: [
          for (final i in state.pending)
            if (_key(i) != _key(issue)) i,
        ],
      ),
    );
  }

  Future<RenumberResult?> renumber(IdIssue issue) async {
    emit(IdCheckState(pending: state.pending, busy: true));
    final res = await _renumber(issue.sheet);
    return res.fold(
      (f) {
        _snoozed.add(_key(issue)); // don't ask again in a loop
        emit(
          IdCheckState(
            pending: [
              for (final i in state.pending)
                if (i.sheet != issue.sheet) i,
            ],
            error: f.message,
          ),
        );
        return null;
      },
      (r) {
        final refs = r.references.entries
            .map((e) => '${e.key} ${e.value}')
            .join(', ');
        final cleared = r.cleared.entries
            .map((e) => '${e.key}: ${e.value.length} cleared')
            .join(', ');
        emit(
          IdCheckState(
            pending: [
              for (final i in state.pending)
                if (i.sheet != issue.sheet) i,
            ],
            message:
                '${r.sheet}: ${r.changed} id(s) shifted'
                '${refs.isEmpty ? '' : '; updated $refs'}'
                '${cleared.isEmpty ? '' : '; links to deleted rows $cleared'}'
                '${r.pendingFiles.isEmpty ? '' : '; ${r.pendingFiles.join(', ')} updated on save'} - save to keep',
          ),
        );
        _changes.notify(DataChange.idsChanged);
        return r;
      },
    );
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
