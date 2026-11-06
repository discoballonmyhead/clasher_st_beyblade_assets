import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../domain/entities/row_lifecycle.dart';
import '../../../domain/entities/structure.dart';
import '../../../domain/usecases/row_lifecycle_usecases.dart';
import '../../../domain/usecases/structure_usecases.dart';
import 'structure_state.dart';

/// New columns and new rows. Each success is announced, so the tab, the field list and the editor
/// refresh themselves; the change also lands in the workbook's change log (engine side).
class StructureCubit extends Cubit<StructureState> {
  StructureCubit({
    required AddColumn addColumn,
    required AddRow addRow,
    DeleteRows? deleteRows,
    required DataChangeNotifier changes,
  }) : _addColumn = addColumn,
       _addRow = addRow,
       _deleteRows = deleteRows,
       _changes = changes,
       super(const StructureState());

  final AddColumn _addColumn;
  final AddRow _addRow;
  final DeleteRows? _deleteRows;
  final DataChangeNotifier _changes;

  static final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,40}$');

  /// Checked here too, so the dialog can say what's wrong before asking the engine.
  static String? validateName(String name) => _name.hasMatch(name.trim())
      ? null
      : 'Start with a letter; letters, digits and _ only (e.g. tipShape)';

  Future<bool> addColumn({
    required List<String> sheets,
    required String name,
    bool optional = false,
    bool inherit = false,
    String? defaultValue,
    String note = '',
  }) async {
    final problem = validateName(name);
    if (problem != null) {
      emit(StructureState(error: problem));
      return false;
    }
    emit(const StructureState(busy: true));
    final res = await _addColumn(
      sheets: sheets,
      name: name.trim(),
      optional: optional,
      inherit: inherit,
      defaultValue: defaultValue,
      note: note,
    );
    return res.fold(
      (f) {
        emit(StructureState(error: f.message));
        return false;
      },
      (_) {
        emit(
          StructureState(
            message:
                'Column ${name.trim()} added to ${sheets.length} tab(s) - save to keep',
          ),
        );
        _changes.notify(DataChange.structureChanged);
        return true;
      },
    );
  }

  /// The new row's id, or null (the reason is in the state).
  Future<String?> addRow(
    String sheet, {
    NewRowMode mode = NewRowMode.empty,
    String? copyFrom,
    Map<String, String>? values,
  }) async {
    emit(const StructureState(busy: true));
    final res = await _addRow(
      sheet,
      values: values,
      copyFrom: copyFrom,
      mode: mode,
    );
    return res.fold(
      (f) {
        emit(StructureState(error: f.message));
        return null;
      },
      (id) {
        final how = switch (mode) {
          NewRowMode.empty => 'new',
          NewRowMode.variant => 'variant of #$copyFrom',
          NewRowMode.copy => 'copy of #$copyFrom',
        };
        emit(StructureState(message: 'Row #$id added ($how) - save to keep'));
        _changes.notify(DataChange.structureChanged);
        return id;
      },
    );
  }

  /// Deletes rows (they go to recently deleted) -> the result, or null (the reason is in the state).
  Future<DeleteResult?> deleteRows(String sheet, List<String> ids) async {
    final delete = _deleteRows;
    if (delete == null || ids.isEmpty) return null;
    emit(const StructureState(busy: true));
    final res = await delete(sheet, ids);
    return res.fold(
      (f) {
        emit(StructureState(error: f.message));
        return null;
      },
      (r) {
        final orphans = r.orphans.isEmpty
            ? ''
            : '. Variants that now point at a deleted parent: ${r.orphans.map((o) => '#$o').join(', ')}';
        emit(
          StructureState(
            message:
                'Deleted ${r.deleted.map((d) => '#$d').join(', ')} (in Recently deleted) - save to keep$orphans',
          ),
        );
        _changes.notify(DataChange.idsChanged);
        return r;
      },
    );
  }
}
