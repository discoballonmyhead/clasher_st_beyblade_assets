import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';

import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_state.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/part_picker_cubit/part_picker_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/part_picker_cubit/part_picker_state.dart';
import 'package:clasher_st/features/beyblade/utils/catalog_randomizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'combined_stats_panel.dart';
import 'part_image_thumb.dart';
import 'part_list_tile.dart';
import 'randomizer_sheet.dart';

/// Builds one bey. [onConfirm] hands back the resolved [Beyblade]; nothing
/// is persisted here. [initialLoadout] pre-fills every slot (used when
/// editing a slot that already has a bey).
///
/// Works for every generation and manufacturer in the catalog: pickers
/// filter by generation and manufacturer, start on the generation of the
/// parts already chosen, and a part with no image still counts as chosen.
class BeybladeBuilderContent extends StatefulWidget {
  const BeybladeBuilderContent(
      {super.key, this.initialLoadout, required this.onConfirm});

  final BeybladeLoadout? initialLoadout;
  final ValueChanged<Beyblade> onConfirm;

  @override
  State<BeybladeBuilderContent> createState() => _BeybladeBuilderContentState();
}

class _BeybladeBuilderContentState extends State<BeybladeBuilderContent> {
  late final BeyBuilderCubit _builderCubit;
  late final BeybladeDataRepo _partsRepo;

  late final PartPickerCubit _bladeCubit;
  late final PartPickerCubit _ratchetCubit;
  late final PartPickerCubit _bitCubit;
  late final PartPickerCubit _lockChipCubit;
  late final PartPickerCubit _overBladeCubit;
  late final PartPickerCubit _metalBladeCubit;
  late final PartPickerCubit _mainBladeCubit;
  late final PartPickerCubit _assistBladeCubit;

  Future<RandomizerSession>? _randomSession;
  bool _rolling = false;
  bool _loadingInitial = false;

  @override
  void initState() {
    super.initState();
    _partsRepo = sl<BeybladeDataRepo>();
    _builderCubit = BeyBuilderCubit(sl<ResolveBeybladeUseCase>());

    PartPickerCubit picker(Future<List<BeybladePart>> Function() load) =>
        PartPickerCubit(load);
    _bladeCubit = picker(() async => await _partsRepo.getAllBlades());
    _ratchetCubit = picker(() async => await _partsRepo.getAllRatchets());
    _bitCubit = picker(() async => await _partsRepo.getAllBits());
    _lockChipCubit = picker(() async => await _partsRepo.getAllLockChips());
    _overBladeCubit = picker(() async => await _partsRepo.getAllOverBlades());
    _metalBladeCubit = picker(() async => await _partsRepo.getAllMetalBlades());
    _mainBladeCubit = picker(() async => await _partsRepo.getAllMainBlades());
    _assistBladeCubit =
        picker(() async => await _partsRepo.getAllAssistBlades());

    final loadout = widget.initialLoadout;
    if (loadout != null) _applyLoadout(loadout);
  }

  @override
  void dispose() {
    _builderCubit.close();
    _bladeCubit.close();
    _ratchetCubit.close();
    _bitCubit.close();
    _lockChipCubit.close();
    _overBladeCubit.close();
    _metalBladeCubit.close();
    _mainBladeCubit.close();
    _assistBladeCubit.close();
    super.dispose();
  }

  /// Loads a saved or random build: every part fetched in parallel, then
  /// applied in one step (mode included), so nothing from the previous
  /// build is left behind.
  Future<void> _applyLoadout(BeybladeLoadout l) async {
    setState(() => _loadingInitial = true);
    Future<T?> fetchOrNull<T>(String? id, Future<T?> Function(String) fetch) =>
        id == null || id.isEmpty ? Future.value(null) : fetch(id);

    final results = await Future.wait<Object?>([
      fetchOrNull(l.bitDataId, _partsRepo.getBitByDataId),
      fetchOrNull(l.bladeDataId, _partsRepo.getBladeByDataId),
      fetchOrNull(l.ratchetDataId, _partsRepo.getRatchetByDataId),
      fetchOrNull(l.lockChipDataId, _partsRepo.getLockChipByDataId),
      fetchOrNull(l.overBladeDataId, _partsRepo.getOverBladeByDataId),
      fetchOrNull(l.metalBladeDataId, _partsRepo.getMetalBladeByDataId),
      fetchOrNull(l.mainBladeDataId, _partsRepo.getMainBladeByDataId),
      fetchOrNull(l.assistBladeDataId, _partsRepo.getAssistBladeByDataId),
    ]);
    if (!mounted) return;

    final separated = l.bladeDataId == null && l.lockChipDataId != null;
    _builderCubit.loadParts(
      bladeMode: separated ? BladeMode.separated : BladeMode.unibody,
      coreMode: l.mainBladeDataId != null ? CoreMode.main : CoreMode.overMetal,
      bit: results[0] as Bit?,
      blade: results[1] as Blade?,
      ratchet: results[2] as Ratchet?,
      lockChip: results[3] as LockChip?,
      overBlade: results[4] as OverBlade?,
      metalBlade: results[5] as MetalBlade?,
      mainBlade: results[6] as MainBlade?,
      assistBlade: results[7] as AssistBlade?,
    );
    setState(() => _loadingInitial = false);
  }

  /// Rolls one complete build with the randomizer's last-used filters.
  Future<void> _randomize() async {
    setState(() => _rolling = true);
    try {
      final session =
          await (_randomSession ??= sl<CatalogRandomizer>().openSession());
      final loadout = session.build(RandomizerChoice.lastUsed.filter);
      if (!mounted) return;
      if (loadout == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No build matches the current random filters.'),
        ));
        return;
      }
      await _applyLoadout(loadout);
    } catch (_) {
      _randomSession = null; // retry with a fresh load next time
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The part catalog could not be loaded.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _rolling = false);
    }
  }

  /// The generation of the parts chosen so far, so pickers open on it.
  String? _generationOf(BeyBuilderState s) {
    final chosen = <BeybladePart?>[
      s.selectedBlade,
      s.selectedLockChip,
      s.selectedMainBlade,
      s.selectedMetalBlade,
      s.selectedBit,
      s.selectedRatchet,
    ].whereType<BeybladePart>();
    return chosen.isEmpty ? null : chosen.first.hobbyGeneration;
  }

  Future<void> _pickAssemblyMode(BeyBuilderState state) async {
    final cs = Theme.of(context).colorScheme;
    await AppDialogWidget.show<void>(
      context,
      title: 'Blade Type',
      headerColor: cs.primaryContainer,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeOption(
            title: 'Single Blade',
            subtitle: 'The basic, all-in-one blade.',
            selected: state.bladeMode == BladeMode.unibody,
            onTap: () {
              _builderCubit.setBladeMode(BladeMode.unibody);
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
          _ModeOption(
            title: 'Lock Chip + Over/Metal Blade',
            subtitle: 'Separated build with an Over Blade and Metal Blade.',
            selected: state.bladeMode == BladeMode.separated &&
                state.coreMode == CoreMode.overMetal,
            onTap: () {
              _builderCubit.setBladeMode(BladeMode.separated);
              _builderCubit.setCoreMode(CoreMode.overMetal);
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
          _ModeOption(
            title: 'Lock Chip + Main Blade',
            subtitle: 'Separated build with a Main Blade instead.',
            selected: state.bladeMode == BladeMode.separated &&
                state.coreMode == CoreMode.main,
            onTap: () {
              _builderCubit.setBladeMode(BladeMode.separated);
              _builderCubit.setCoreMode(CoreMode.main);
              Navigator.of(context, rootNavigator: true).pop();
            },
          ),
        ],
      ),
    );
  }

  /// Opens [cubit]'s search + list. Fixed height: AppDialogWidget's content
  /// area is its own unbounded scroll view, and the list inside needs a
  /// bounded height to use Expanded.
  Future<void> _openPicker({
    required String title,
    required PartPickerCubit cubit,
    required BeybladePart? selected,
    required ValueChanged<BeybladePart> onSelect,
  }) {
    // Built-in ratchet on both blade and bit is impossible: hide the parts
    // that would clash with what's already picked.
    final s = _builderCubit.state;
    String? hiddenNote;
    if (identical(cubit, _bitCubit)) {
      final blade = s.bladeMode == BladeMode.unibody ? s.selectedBlade : null;
      final clash = blade?.hasIntegratedRatchet ?? false;
      cubit
          .setExclude(clash ? (p) => p is Bit && p.hasIntegratedRatchet : null);
      if (clash) {
        hiddenNote = 'Bits with a built-in ratchet are hidden: '
            '${blade!.name} already has one.';
      }
    } else if (identical(cubit, _bladeCubit)) {
      final bit = s.selectedBit;
      final clash = bit?.hasIntegratedRatchet ?? false;
      cubit.setExclude(
          clash ? (p) => p is Blade && p.hasIntegratedRatchet : null);
      if (clash) {
        hiddenNote = 'Blades with a built-in ratchet are hidden: '
            '${bit!.name} already has one.';
      }
    } else if (identical(cubit, _ratchetCubit)) {
      // A blade / assist blade that only fits a simple ratchet: offer only
      // those. Reset otherwise, so the filter never sticks to a later build.
      final needer = s.simpleRatchetRequiredBy;
      cubit.setExclude(
          needer != null ? (p) => p is Ratchet && !p.isSimple : null);
      if (needer != null) {
        hiddenNote = 'Only simple ratchets are shown: ${needer.name} '
            'needs a simple ratchet.';
      }
    }
    // First open: start on the generation already in the build, so an X
    // build isn't offered Burst parts first. "All" is one tap away.
    final gen = _generationOf(_builderCubit.state);
    if (cubit.state.all.isEmpty &&
        cubit.state.generation == null &&
        gen != null) {
      cubit.setGeneration(gen);
    }
    return AppDialogWidget.show<void>(
      context,
      title: title,
      content: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: _PartPickerDialogBody(
          cubit: cubit,
          hiddenNote: hiddenNote,
          selectedDataId: selected?.dataId,
          onSelect: (part) {
            onSelect(part);
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
      ),
    );
  }

  _TileSpec _tile(String label, BeybladePart? part, PartPickerCubit cubit,
          ValueChanged<BeybladePart> onSelect) =>
      _TileSpec(
        label: label,
        part: part,
        onTap: () => _openPicker(
          title: 'Select $label',
          cubit: cubit,
          selected: part,
          onSelect: onSelect,
        ),
      );

  /// Exactly the tiles the current mode needs, in build order.
  List<_TileSpec> _tileSpecs(BeyBuilderState s) {
    final c = _builderCubit;
    final ratchet = _tile(
        s.requiresSimpleRatchet ? 'Simple Ratchet' : 'Ratchet',
        s.selectedRatchet,
        _ratchetCubit,
        (p) => c.selectRatchet(p as Ratchet));
    final bit =
        _tile('Bit', s.selectedBit, _bitCubit, (p) => c.selectBit(p as Bit));

    if (s.bladeMode == BladeMode.unibody) {
      return [
        _tile('Blade', s.selectedBlade, _bladeCubit,
            (p) => c.selectBlade(p as Blade)),
        if (!s.ratchetDisabled) ratchet,
        bit,
      ];
    }
    final lock = _tile('Lock Chip', s.selectedLockChip, _lockChipCubit,
        (p) => c.selectLockChip(p as LockChip));
    final assist = _tile('Assist Blade', s.selectedAssistBlade,
        _assistBladeCubit, (p) => c.selectAssistBlade(p as AssistBlade));
    return [
      lock,
      if (s.coreMode == CoreMode.main)
        _tile('Main Blade', s.selectedMainBlade, _mainBladeCubit,
            (p) => c.selectMainBlade(p as MainBlade))
      else ...[
        _tile('Over Blade', s.selectedOverBlade, _overBladeCubit,
            (p) => c.selectOverBlade(p as OverBlade)),
        _tile('Metal Blade', s.selectedMetalBlade, _metalBladeCubit,
            (p) => c.selectMetalBlade(p as MetalBlade)),
      ],
      assist,
      if (!s.ratchetDisabled) ratchet,
      bit,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;

    return BlocProvider.value(
      value: _builderCubit,
      child: BlocBuilder<BeyBuilderCubit, BeyBuilderState>(
        builder: (context, state) {
          final tiles = _tileSpecs(state);
          final missing = _builderCubit.missingSlots;
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  rc.horizontalPadding, rc.sm, rc.horizontalPadding, rc.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: HoloSectionLabel(title: 'Build')),
                      SizedBox(width: rc.sm),
                      IconButton.filledTonal(
                        tooltip: 'Random build',
                        icon: _rolling
                            ? const SizedBox(
                                width: 20, height: 20, child: BeybladeSpinner())
                            : const Icon(Icons.casino_outlined),
                        onPressed:
                            _rolling || _loadingInitial ? null : _randomize,
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Change blade type',
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: () => _pickAssemblyMode(state),
                      ),
                    ],
                  ),
                  SizedBox(height: rc.md),
                  if (_loadingInitial)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: rc.xl),
                      child: const Center(child: BeybladeSpinner()),
                    )
                  else
                    for (var i = 0; i < tiles.length; i++) ...[
                      _ConnectedTile(spec: tiles[i]),
                      if (i != tiles.length - 1) const _Connector(),
                    ],
                  if (state.resolved != null) ...[
                    SizedBox(height: rc.lg),
                    CombinedStatsPanel(beyblade: state.resolved!),
                  ],
                  SizedBox(height: rc.lg),
                  if (missing.isNotEmpty && !_loadingInitial)
                    Padding(
                      padding: EdgeInsets.only(bottom: rc.sm),
                      child: Text(
                        'Still needed: ${missing.join(', ')}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: rc.bodySM, color: cs.onSurfaceVariant),
                      ),
                    ),
                  HoloActionButton(
                    label: 'Confirm',
                    icon: Icons.check,
                    expand: true,
                    isLoading: state.resolving,
                    onPressed: state.resolved == null
                        ? null
                        : () => widget.onConfirm(state.resolved!),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _TileSpec {
  const _TileSpec(
      {required this.label, required this.part, required this.onTap});

  final String label;
  final BeybladePart? part;
  final VoidCallback onTap;
}

/// A slot in the build. "Filled" means a part is chosen, whether or not it
/// has an image: older generations often don't, and those used to look
/// unselected.
class _ConnectedTile extends StatelessWidget {
  const _ConnectedTile({required this.spec});

  final _TileSpec spec;

  static const _imageSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final part = spec.part;
    final filled = part != null;
    final variant = part?.variantLabel?.trim();
    final detail = part == null
        ? null
        : [
            if (part.hobbyGeneration.trim().isNotEmpty) part.hobbyGeneration,
            if (variant != null && variant.isNotEmpty) variant,
          ].join(' · ');

    return Material(
      color: filled ? cs.surfaceContainerHighest : Colors.transparent,
      shape: ChamferBorder.tab(
        cut: 10,
        side: filled ? BorderSide.none : BorderSide(color: cs.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: spec.onTap,
        child: Padding(
          padding: EdgeInsets.all(rc.sm),
          child: Row(
            children: [
              if (filled)
                PartImageThumb(
                  imageUrl: preferredThumbUrl(part),
                  size: _imageSize,
                  scale: imageScaleFor(part),
                )
              else
                Container(
                  width: _imageSize,
                  height: _imageSize,
                  decoration: ShapeDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: const ChamferBorder.tab(cut: 8),
                  ),
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: cs.onSurfaceVariant),
                ),
              SizedBox(width: rc.sm * 1.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(spec.label,
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Text(
                      part?.name ?? 'Tap to select',
                      style: tt.bodyMedium?.copyWith(
                          fontWeight: filled ? FontWeight.w700 : null,
                          color: filled ? cs.onSurface : cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line between tiles, aligned under the fixed-size image's centre.
class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return Padding(
      padding: EdgeInsets.only(
          left: rc.sm + _ConnectedTile._imageSize / 2 - 1,
          top: rc.sm / 2,
          bottom: rc.sm / 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(width: 2, height: 12, color: cs.outline),
      ),
    );
  }
}

/// Search, generation / manufacturer chips, and the list.
class _PartPickerDialogBody extends StatefulWidget {
  const _PartPickerDialogBody(
      {required this.cubit,
      required this.selectedDataId,
      required this.onSelect,
      this.hiddenNote});

  final PartPickerCubit cubit;

  /// Why some parts aren't listed (e.g. two built-in ratchets).
  final String? hiddenNote;
  final String? selectedDataId;
  final ValueChanged<BeybladePart> onSelect;

  @override
  State<_PartPickerDialogBody> createState() => _PartPickerDialogBodyState();
}

class _PartPickerDialogBodyState extends State<_PartPickerDialogBody> {
  late final TextEditingController _search =
      TextEditingController(text: widget.cubit.state.query);

  @override
  void initState() {
    super.initState();
    if (widget.cubit.state.all.isEmpty) widget.cubit.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return BlocBuilder<PartPickerCubit, PartPickerState>(
      bloc: widget.cubit,
      builder: (context, state) {
        Widget chips(List<String> values, String? selected,
                ValueChanged<String?> onTap) =>
            values.length < 2
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(bottom: rc.xs),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: selected == null,
                            onSelected: (_) => onTap(null),
                          ),
                          for (final v in values) ...[
                            SizedBox(width: rc.xs),
                            ChoiceChip(
                              label: Text(v),
                              selected: selected == v,
                              onSelected: (_) => onTap(v),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: rc.sm),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                    hintText: 'Search name, code or edition…',
                    prefixIcon: Icon(Icons.search)),
                onChanged: widget.cubit.search,
              ),
            ),
            if (widget.hiddenNote != null)
              Padding(
                padding: EdgeInsets.only(bottom: rc.xs),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 16, color: cs.onSurfaceVariant),
                  SizedBox(width: rc.xs),
                  Expanded(
                    child: Text(widget.hiddenNote!,
                        style: TextStyle(
                            fontSize: rc.bodySM, color: cs.onSurfaceVariant)),
                  ),
                ]),
              ),
            chips(state.generations, state.generation,
                widget.cubit.setGeneration),
            chips(state.manufacturers, state.manufacturer,
                widget.cubit.setManufacturer),
            Expanded(
              child: () {
                if (state.loading) {
                  return const Center(child: BeybladeSpinner());
                }
                if (state.error != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!, style: TextStyle(color: cs.error)),
                        SizedBox(height: rc.sm),
                        HoloActionButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          dense: true,
                          variant: HoloButtonVariant.outline,
                          onPressed: widget.cubit.load,
                        ),
                      ],
                    ),
                  );
                }
                if (state.results.isEmpty) {
                  return Center(
                    child: Text(
                      state.all.isEmpty
                          ? 'No parts of this type in the catalog'
                          : 'No matches',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: state.results.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (context, i) {
                    final part = state.results[i];
                    return PartListTile(
                      part: part,
                      selected: part.dataId == widget.selectedDataId,
                      onTap: () => widget.onSelect(part),
                    );
                  },
                );
              }(),
            ),
          ],
        );
      },
    );
  }
}
