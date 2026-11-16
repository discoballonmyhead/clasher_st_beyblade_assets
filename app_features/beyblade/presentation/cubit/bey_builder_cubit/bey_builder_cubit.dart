import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bey_builder_state.dart';

/// Orchestrates picking parts across the builder's tabs and keeps a
/// live-resolved [Beyblade] preview in sync via [ResolveBeybladeUseCase].
/// No new domain logic here — purely presentation-layer orchestration on
/// top of what BeybladeLoadout/ResolveBeybladeUseCase already do.
class BeyBuilderCubit extends Cubit<BeyBuilderState> {
  BeyBuilderCubit(this._resolveBeyblade) : super(const BeyBuilderState());

  final ResolveBeybladeUseCase _resolveBeyblade;

  /// Bumped on every resolve attempt so a slow, now-superseded resolution
  /// can't overwrite a faster, more recent one — same pattern as
  /// PartSearchCubit's _seq.
  int _resolveSeq = 0;

  /// Switching modes replaces the state wholesale rather than clearing
  /// individual fields — the old mode's selections are simply not
  /// carried over, since they're meaningless in the new mode. Ratchet
  /// and Bit are the only things orthogonal to blade mode, so those
  /// carry over.
  void setBladeMode(BladeMode mode) {
    if (mode == state.bladeMode) return;
    emit(BeyBuilderState(
        bladeMode: mode,
        coreMode: state.coreMode,
        selectedRatchet: state.selectedRatchet,
        selectedBit: state.selectedBit));
    _resolve();
  }

  void setCoreMode(CoreMode mode) {
    if (mode == state.coreMode) return;
    emit(BeyBuilderState(
      bladeMode: state.bladeMode,
      coreMode: mode,
      selectedRatchet: state.selectedRatchet,
      selectedBit: state.selectedBit,
      selectedLockChip: state.selectedLockChip,
      selectedAssistBlade: state.selectedAssistBlade,
    ));
    _resolve();
  }

  /// A blade with a built-in ratchet drops a bit that also has one
  /// (see [integratedRatchetConflict]); the bit picker hides those bits.
  /// A blade that needs a simple ratchet drops a ratchet that isn't one
  /// (see [simpleRatchetConflict]); the ratchet picker then offers only
  /// simple ratchets.
  void selectBlade(Blade blade) {
    emit(state.copyWith(
      selectedBlade: blade,
      clearRatchet: blade.hasIntegratedRatchet ||
          simpleRatchetConflict(state.selectedRatchet, blade: blade),
      clearBit: integratedRatchetConflict(blade, state.selectedBit),
    ));
    _resolve();
  }

  /// Ignored when the top needs a simple ratchet and [ratchet] isn't one:
  /// the picker hides those, this only guards other callers.
  void selectRatchet(Ratchet ratchet) {
    if (state.requiresSimpleRatchet && !ratchet.isSimple) return;
    emit(state.copyWith(selectedRatchet: ratchet));
    _resolve();
  }

  void selectBit(Bit bit) {
    // Bit's own integrated ratchet was never checked here before — fixed
    // alongside this rebuild, since it's the same rule as Blade's.
    // A built-in-ratchet bit drops a built-in-ratchet blade (unibody only;
    // separated tops have no ratchet of their own).
    final conflict = state.bladeMode == BladeMode.unibody &&
        integratedRatchetConflict(state.selectedBlade, bit);
    emit(state.copyWith(
      selectedBit: bit,
      clearRatchet: bit.hasIntegratedRatchet,
      clearBlade: conflict,
    ));
    _resolve();
  }

  void selectLockChip(LockChip lockChip) {
    emit(state.copyWith(selectedLockChip: lockChip));
    _resolve();
  }

  void selectOverBlade(OverBlade overBlade) {
    emit(state.copyWith(selectedOverBlade: overBlade));
    _resolve();
  }

  void selectMetalBlade(MetalBlade metalBlade) {
    emit(state.copyWith(selectedMetalBlade: metalBlade));
    _resolve();
  }

  void selectMainBlade(MainBlade mainBlade) {
    emit(state.copyWith(selectedMainBlade: mainBlade));
    _resolve();
  }

  /// Like [selectBlade]: an assist blade that needs a simple ratchet drops
  /// a ratchet that isn't one.
  void selectAssistBlade(AssistBlade assistBlade) {
    emit(state.copyWith(
      selectedAssistBlade: assistBlade,
      clearRatchet: simpleRatchetConflict(state.selectedRatchet,
          assistBlade: assistBlade),
    ));
    _resolve();
  }

  /// Replaces the whole selection in one step: one emit, one resolve.
  /// Used to load a saved build or a random one. Unlike calling the
  /// select* methods one by one, this also switches [BladeMode] (the old
  /// path never switched back to unibody, so a single-blade build loaded
  /// into a builder in Lock Chip mode was assembled as a separated one)
  /// and drops every previous pick, so nothing from the last build leaks
  /// into this one.
  void loadParts({
    required BladeMode bladeMode,
    CoreMode coreMode = CoreMode.overMetal,
    Blade? blade,
    Ratchet? ratchet,
    Bit? bit,
    LockChip? lockChip,
    OverBlade? overBlade,
    MetalBlade? metalBlade,
    MainBlade? mainBlade,
    AssistBlade? assistBlade,
  }) {
    final unibody = bladeMode == BladeMode.unibody;
    // An impossible saved build (two built-in ratchets) loads without its
    // bit, so the user picks a compatible one instead of saving it again.
    if (unibody && integratedRatchetConflict(blade, bit)) bit = null;
    final integrated = (unibody && (blade?.hasIntegratedRatchet ?? false)) ||
        (bit?.hasIntegratedRatchet ?? false);
    // A saved build from before the simple-ratchet rule (or from data that
    // changed since) loads without its ratchet, so a simple one gets picked.
    if (simpleRatchetConflict(ratchet,
        blade: unibody ? blade : null,
        assistBlade: unibody ? null : assistBlade)) {
      ratchet = null;
    }
    emit(BeyBuilderState(
      bladeMode: bladeMode,
      coreMode: coreMode,
      selectedBlade: unibody ? blade : null,
      selectedRatchet: integrated ? null : ratchet,
      selectedBit: bit,
      selectedLockChip: unibody ? null : lockChip,
      selectedOverBlade:
          !unibody && coreMode == CoreMode.overMetal ? overBlade : null,
      selectedMetalBlade:
          !unibody && coreMode == CoreMode.overMetal ? metalBlade : null,
      selectedMainBlade:
          !unibody && coreMode == CoreMode.main ? mainBlade : null,
      selectedAssistBlade: unibody ? null : assistBlade,
    ));
    _resolve();
  }

  void reset() {
    // Invalidate any resolve still in flight, or it would repopulate the
    // preview after the reset.
    _resolveSeq++;
    emit(const BeyBuilderState());
  }

  /// Slots the current mode still needs, in display order. Empty when the
  /// build is complete. Drives the "Still needed: ..." hint.
  List<String> get missingSlots {
    final s = state;
    final out = <String>[];
    if (s.bladeMode == BladeMode.unibody) {
      if (s.selectedBlade == null) out.add('Blade');
    } else {
      if (s.selectedLockChip == null) out.add('Lock Chip');
      if (s.coreMode == CoreMode.main) {
        if (s.selectedMainBlade == null) out.add('Main Blade');
      } else {
        if (s.selectedOverBlade == null) out.add('Over Blade');
        if (s.selectedMetalBlade == null) out.add('Metal Blade');
      }
      if (s.selectedAssistBlade == null) out.add('Assist Blade');
    }
    if (!s.ratchetDisabled && s.selectedRatchet == null) {
      out.add(s.requiresSimpleRatchet ? 'Simple Ratchet' : 'Ratchet');
    }
    if (s.selectedBit == null) out.add('Bit');
    return out;
  }

  Future<void> _resolve() async {
    final mySeq = ++_resolveSeq;
    final loadout = _buildLoadout();

    if (loadout == null) {
      emit(state.copyWith(clearResolved: true));
      return;
    }

    emit(state.copyWith(resolving: true));
    final resolved = await _resolveBeyblade(loadout);
    if (mySeq != _resolveSeq) return; // superseded by a newer selection
    emit(state.copyWith(resolving: false, resolved: resolved));
  }

  /// Null until every slot the current mode requires is filled —
  /// deliberately never guesses at a partial build.
  BeybladeLoadout? _buildLoadout() {
    final bit = state.selectedBit;
    if (bit == null) return null;
    // A ratchet is required unless the blade or the bit has one built in.
    // ResolveBeybladeUseCase doesn't check this, so before this line a
    // build with no ratchet resolved as complete and could be registered.
    if (!state.ratchetDisabled && state.selectedRatchet == null) return null;
    // Never resolve a top that needs a simple ratchet on another one.
    if (state.requiresSimpleRatchet &&
        !(state.selectedRatchet?.isSimple ?? true)) {
      return null;
    }

    if (state.bladeMode == BladeMode.unibody) {
      final blade = state.selectedBlade;
      if (blade == null) return null;
      if (integratedRatchetConflict(blade, bit)) return null;
      return BeybladeLoadout(
          bladeDataId: blade.dataId,
          ratchetDataId: state.selectedRatchet?.dataId,
          bitDataId: bit.dataId);
    }

    final lockChip = state.selectedLockChip;
    final assistBlade = state.selectedAssistBlade;
    if (lockChip == null || assistBlade == null) return null;

    String? overId, metalId, mainId;
    if (state.coreMode == CoreMode.main) {
      final mainBlade = state.selectedMainBlade;
      if (mainBlade == null) return null;
      mainId = mainBlade.dataId;
    } else {
      final overBlade = state.selectedOverBlade;
      final metalBlade = state.selectedMetalBlade;
      if (overBlade == null || metalBlade == null) return null;
      overId = overBlade.dataId;
      metalId = metalBlade.dataId;
    }

    return BeybladeLoadout(
      ratchetDataId: state.selectedRatchet?.dataId,
      bitDataId: bit.dataId,
      lockChipDataId: lockChip.dataId,
      overBladeDataId: overId,
      metalBladeDataId: metalId,
      mainBladeDataId: mainId,
      assistBladeDataId: assistBlade.dataId,
    );
  }
}
