import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:equatable/equatable.dart';

/// Which shape the top of the build takes — the "+" icon next to the
/// Blade slot toggles this.
enum BladeMode { unibody, separated }

/// Only meaningful when [BeyBuilderState.bladeMode] is separated — which
/// of the two mutually-exclusive middle sections is active.
enum CoreMode { overMetal, main }

/// The build in progress. [resolved] is only non-null once every slot
/// the current mode requires is filled, re-derived after every single
/// selection change so the stack preview and stats panel always match
/// exactly what's currently picked.
class BeyBuilderState extends Equatable {
  const BeyBuilderState({
    this.bladeMode = BladeMode.unibody,
    this.coreMode = CoreMode.overMetal,
    this.selectedBlade,
    this.selectedRatchet,
    this.selectedBit,
    this.selectedLockChip,
    this.selectedOverBlade,
    this.selectedMetalBlade,
    this.selectedMainBlade,
    this.selectedAssistBlade,
    this.resolving = false,
    this.resolved,
  });

  final BladeMode bladeMode;
  final CoreMode coreMode;

  final Blade? selectedBlade;
  final Ratchet? selectedRatchet;
  final Bit? selectedBit;
  final LockChip? selectedLockChip;
  final OverBlade? selectedOverBlade;
  final MetalBlade? selectedMetalBlade;
  final MainBlade? selectedMainBlade;
  final AssistBlade? selectedAssistBlade;

  final bool resolving;
  final Beyblade? resolved;

  bool get isComplete => resolved != null;

  /// True when either the unibody blade or the selected bit has an
  /// integrated ratchet — the Ratchet slot should be hidden/disabled in
  /// the UI when this is true.
  bool get ratchetDisabled =>
      (bladeMode == BladeMode.unibody &&
          (selectedBlade?.hasIntegratedRatchet ?? false)) ||
      (selectedBit?.hasIntegratedRatchet ?? false);

  /// The part that only fits a simple ratchet: the blade in a single-blade
  /// build, the assist blade in a lock chip build. Null when nothing needs
  /// one (any ratchet is fine).
  BeybladePart? get simpleRatchetRequiredBy {
    if (bladeMode == BladeMode.unibody) {
      final b = selectedBlade;
      return (b?.requiresSimpleRatchet ?? false) ? b : null;
    }
    final a = selectedAssistBlade;
    return (a?.requiresSimpleRatchet ?? false) ? a : null;
  }

  /// Only simple ratchets ([Ratchet.isSimple]) may be picked.
  bool get requiresSimpleRatchet => simpleRatchetRequiredBy != null;

  BeyBuilderState copyWith({
    Blade? selectedBlade,
    bool clearBlade = false,
    bool clearBit = false,
    Ratchet? selectedRatchet,
    bool clearRatchet = false,
    Bit? selectedBit,
    LockChip? selectedLockChip,
    OverBlade? selectedOverBlade,
    MetalBlade? selectedMetalBlade,
    MainBlade? selectedMainBlade,
    AssistBlade? selectedAssistBlade,
    bool? resolving,
    Beyblade? resolved,
    bool clearResolved = false,
  }) =>
      BeyBuilderState(
        bladeMode: bladeMode,
        coreMode: coreMode,
        selectedBlade:
            clearBlade ? null : (selectedBlade ?? this.selectedBlade),
        selectedRatchet:
            clearRatchet ? null : (selectedRatchet ?? this.selectedRatchet),
        selectedBit: clearBit ? null : (selectedBit ?? this.selectedBit),
        selectedLockChip: selectedLockChip ?? this.selectedLockChip,
        selectedOverBlade: selectedOverBlade ?? this.selectedOverBlade,
        selectedMetalBlade: selectedMetalBlade ?? this.selectedMetalBlade,
        selectedMainBlade: selectedMainBlade ?? this.selectedMainBlade,
        selectedAssistBlade: selectedAssistBlade ?? this.selectedAssistBlade,
        resolving: resolving ?? this.resolving,
        resolved: clearResolved ? null : (resolved ?? this.resolved),
      );

  @override
  List<Object?> get props => [
        bladeMode,
        coreMode,
        selectedBlade,
        selectedRatchet,
        selectedBit,
        selectedLockChip,
        selectedOverBlade,
        selectedMetalBlade,
        selectedMainBlade,
        selectedAssistBlade,
        resolving,
        resolved,
      ];
}
