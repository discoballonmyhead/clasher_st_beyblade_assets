import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/deck_slot_cubit/beyblade_deck_slots_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the fixed local deck slots: loads them, resolves each stored
/// loadout into a live [Beyblade] so the UI never resolves anything
/// itself, and saves/clears individual slots. Reloads all slots after
/// any write rather than patching one in place -- there are only ever a
/// handful, so re-resolving is cheap and removes a way for a slot's
/// displayed state to drift from what's stored.
///
/// Now depends on ManageDeckSlotsUseCase instead of the deleted
/// DeckSlotsRepository.
class DeckSlotsCubit extends Cubit<DeckSlotsState> {
  DeckSlotsCubit(this._manageDeckSlots, this._resolveBeyblade)
      : super(const DeckSlotsState());

  final ManageDeckSlotsUseCase _manageDeckSlots;
  final ResolveBeybladeUseCase _resolveBeyblade;

  Future<void> load() async {
    emit(const DeckSlotsState(loading: true));
    final slots = await _manageDeckSlots.getAllDeckSlots();
    final resolved = await Future.wait(slots.map((s) async {
      final bey = s.loadout == null ? null : await _resolveBeyblade(s.loadout!);
      return ResolvedDeckSlot(index: s.index, beyblade: bey);
    }));
    emit(DeckSlotsState(loading: false, slots: resolved));
  }

  Future<void> saveToSlot(int index, Beyblade beyblade) async {
    await _manageDeckSlots.saveDeckSlot(index, beyblade.loadout);
    await load();
  }

  Future<void> clearSlot(int index) async {
    await _manageDeckSlots.clearDeckSlot(index);
    await load();
  }
}
