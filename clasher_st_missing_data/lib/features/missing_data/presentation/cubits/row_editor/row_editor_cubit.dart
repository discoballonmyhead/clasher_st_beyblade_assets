import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../../../core/services/file_picker_service.dart';
import '../../../domain/usecases/row_usecases.dart';
import 'row_editor_state.dart';

/// The row being edited: draft values, apply (stamps last edited), images.
class RowEditorCubit extends Cubit<RowEditorState> {
  RowEditorCubit({
    required GetRow getRow,
    required UpdateRow updateRow,
    required SetRowImage setImage,
    required GetParentImage parentImage,
    required FilePickerService picker,
    required DataChangeNotifier changes,
  }) : _getRow = getRow,
       _updateRow = updateRow,
       _setImage = setImage,
       _parentImage = parentImage,
       _picker = picker,
       _changes = changes,
       super(const RowEditorState()) {
    _sub = changes.stream.listen((c) {
      if (c == DataChange.workbookOpened || c == DataChange.idsChanged) {
        emit(
          const RowEditorState(),
        ); // never keep editing a row under an id that may be another row's now
      } else if ((c == DataChange.undone ||
              c == DataChange.wikiFinished ||
              c == DataChange.filled ||
              c == DataChange.structureChanged) &&
          state.detail != null &&
          !state.hasDrafts) {
        load(state.sheet!, state.detail!.id);
      }
    });
  }

  final GetRow _getRow;
  final UpdateRow _updateRow;
  final SetRowImage _setImage;
  final GetParentImage _parentImage;
  final FilePickerService _picker;
  final DataChangeNotifier _changes;
  late final StreamSubscription<DataChange> _sub;

  Future<void> load(String sheet, String id) async {
    emit(state.copyWith(sheet: sheet, loading: true));
    final res = await _getRow(sheet, id);
    res.fold(
      (f) => emit(state.copyWith(loading: false, error: f.message)),
      (d) => emit(
        RowEditorState(sheet: sheet, detail: d, newImage: state.newImage),
      ),
    );
  }

  void edit(String field, String value) {
    final original = state.detail?.display(field) ?? '';
    final drafts = {...state.drafts};
    value.trim() == original.trim()
        ? drafts.remove(field)
        : drafts[field] = value;
    emit(state.copyWith(drafts: drafts));
  }

  void discard() => emit(state.copyWith(drafts: const {}));

  Future<bool> apply() async {
    final d = state.detail;
    if (d == null || !state.hasDrafts) return false;
    emit(state.copyWith(saving: true));
    final res = await _updateRow(state.sheet!, d.id, state.drafts);
    return res.fold(
      (f) {
        emit(state.copyWith(saving: false, error: f.message));
        return false;
      },
      (n) async {
        emit(
          state.copyWith(
            saving: false,
            drafts: const {},
            message: '$n field(s) changed - save to keep',
          ),
        );
        _changes.notify(DataChange.rowsEdited);
        await load(state.sheet!, d.id);
        return true;
      },
    );
  }

  Future<void> pickImage() async {
    final bytes = await _picker.pickImage();
    if (bytes != null) emit(state.copyWith(newImage: () => bytes));
  }

  Future<void> useParentImage() async {
    final d = state.detail;
    if (d == null) return;
    final res = await _parentImage(state.sheet!, d.id);
    res.fold((f) => emit(state.copyWith(error: f.message)), (b) {
      if (b == null) {
        emit(state.copyWith(message: 'This row has no parent with an image'));
      } else {
        emit(state.copyWith(newImage: () => b));
      }
    });
  }

  void clearNewImage() => emit(state.copyWith(newImage: () => null));

  Future<void> putImage({String? url}) async {
    final d = state.detail;
    if (d == null) return;
    final bytes = state.newImage;
    if (url == null && bytes == null) return;
    emit(state.copyWith(saving: true));
    final res = url != null
        ? await _setImage.fromUrl(state.sheet!, d.id, url)
        : await _setImage(state.sheet!, d.id, bytes!);
    await res.fold(
      (f) async => emit(state.copyWith(saving: false, error: f.message)),
      (_) async {
        emit(
          state.copyWith(
            saving: false,
            newImage: () => null,
            message: 'Image put on #${d.id} - save to keep',
          ),
        );
        _changes.notify(DataChange.rowsEdited);
        await load(state.sheet!, d.id);
      },
    );
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
