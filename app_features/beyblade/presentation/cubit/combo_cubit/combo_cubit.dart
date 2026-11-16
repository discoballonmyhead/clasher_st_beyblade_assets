import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Import your entities and use cases...

class CombosState extends Equatable {
  const CombosState({this.loading = true, this.combos = const []});
  final bool loading;
  final List<Combo> combos;

  @override
  List<Object?> get props => [loading, combos];
}

class CombosCubit extends Cubit<CombosState> {
  // Clean Architecture: Depends on the Use Case
  CombosCubit(this._manageCombos) : super(const CombosState());

  final ManageCombosUseCase _manageCombos;

  Future<void> load() async {
    emit(const CombosState(loading: true));
    final combos = await _manageCombos.getAllCombos();
    emit(CombosState(loading: false, combos: combos));
  }

  /// Returns the combo it created, so callers that need its id (saving a
  /// registered deck as a Deck) don't have to guess it from the list.
  /// Callers that ignore the result are unaffected.
  Future<Combo> create(String name, BeybladeLoadout loadout) async {
    final combo = await _manageCombos.createCombo(name, loadout);
    await load();
    return combo;
  }

  Future<void> delete(String id) async {
    await _manageCombos.deleteCombo(id);
    await load();
  }
}
