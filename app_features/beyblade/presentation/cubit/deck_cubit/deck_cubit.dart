import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DecksState extends Equatable {
  const DecksState(
      {this.loading = true, this.decks = const [], this.errorMessage});

  final bool loading;
  final List<Deck> decks;
  final String? errorMessage;

  @override
  List<Object?> get props => [loading, decks, errorMessage];
}

/// Depends on ManageDecksUseCase, not the deleted DecksRepository -- the
/// deck/combo/deck-slot repositories were all folded into BeybladeDataRepo
/// and this cubit had not been updated to follow.
class DecksCubit extends Cubit<DecksState> {
  DecksCubit(this._manageDecks) : super(const DecksState());

  final ManageDecksUseCase _manageDecks;

  Future<void> load() async {
    emit(const DecksState(loading: true));
    final decks = await _manageDecks.getAllDecks();
    emit(DecksState(loading: false, decks: decks));
  }

  /// True on success; false with state.errorMessage set when the combo
  /// count didn't meet the minimum, so the caller can decide whether to
  /// navigate without wrapping a cubit call in its own try/catch.
  Future<bool> create(String name, List<String> comboIds) async {
    try {
      await _manageDecks.createDeck(name, comboIds);
      await load();
      return true;
    } on ArgumentError catch (e) {
      emit(DecksState(
          loading: false,
          decks: state.decks,
          errorMessage: e.message.toString()));
      return false;
    }
  }

  Future<void> delete(String id) async {
    await _manageDecks.deleteDeck(id);
    await load();
  }
}
