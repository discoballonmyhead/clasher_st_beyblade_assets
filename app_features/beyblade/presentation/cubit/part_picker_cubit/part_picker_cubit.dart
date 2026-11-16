import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'part_picker_state.dart';

/// One part type's "browse every part, filter as you type". Loads the
/// whole (small) catalog for its type once, then filters in memory:
/// search text, generation and manufacturer.
///
/// Parameterized by [loadAll] rather than a part-type generic, so the same
/// cubit class backs every slot (Blade/Ratchet/Bit/...).
class PartPickerCubit extends Cubit<PartPickerState> {
  PartPickerCubit(this._loadAll) : super(const PartPickerState());

  final Future<List<BeybladePart>> Function() _loadAll;

  /// Parts that can't go with the rest of the build right now (e.g. bits
  /// with a built-in ratchet when the blade already has one). Hidden from
  /// the list; null hides nothing.
  bool Function(BeybladePart part)? _exclude;

  /// How many loaded parts [setExclude] is hiding, for a short note.
  int get excludedCount {
    final ex = _exclude;
    return ex == null ? 0 : state.all.where(ex).length;
  }

  void setExclude(bool Function(BeybladePart part)? exclude) {
    _exclude = exclude;
    emit(state.copyWith(results: _filter(state)));
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final all = await _loadAll();
      if (isClosed) return;
      final gens = {for (final p in all) p.hobbyGeneration}
        ..removeWhere((g) => g.trim().isEmpty);
      final makers = {for (final p in all) p.manufacturer}
        ..removeWhere((m) => m.trim().isEmpty);
      // Drop a preset filter that this part type has nothing for, so a
      // generation preset can never produce a mysteriously empty list.
      final keepGen =
          state.generation != null && gens.contains(state.generation);
      final keepMaker =
          state.manufacturer != null && makers.contains(state.manufacturer);
      final next = state.copyWith(
        loading: false,
        all: all,
        generations: gens.toList()..sort(),
        manufacturers: makers.toList()..sort(),
        clearGeneration: !keepGen,
        clearManufacturer: !keepMaker,
      );
      emit(next.copyWith(results: _filter(next)));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
          loading: false, error: 'Could not load parts. Try again.'));
    }
  }

  void search(String query) {
    final next = state.copyWith(query: query);
    emit(next.copyWith(results: _filter(next)));
  }

  /// Null shows every generation.
  void setGeneration(String? generation) {
    final next = generation == null
        ? state.copyWith(clearGeneration: true)
        : state.copyWith(generation: generation);
    emit(next.copyWith(results: _filter(next)));
  }

  /// Null shows every manufacturer.
  void setManufacturer(String? manufacturer) {
    final next = manufacturer == null
        ? state.copyWith(clearManufacturer: true)
        : state.copyWith(manufacturer: manufacturer);
    emit(next.copyWith(results: _filter(next)));
  }

  List<BeybladePart> _filter(PartPickerState s) {
    final q = s.query.trim().toLowerCase();
    final ex = _exclude;
    return [
      for (final p in s.all)
        if ((ex == null || !ex(p)) &&
            (s.generation == null || p.hobbyGeneration == s.generation) &&
            (s.manufacturer == null || p.manufacturer == s.manufacturer) &&
            (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.code.toLowerCase().contains(q) ||
                (p.variantLabel?.toLowerCase().contains(q) ?? false)))
          p,
    ];
  }
}
