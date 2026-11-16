import 'dart:async';
import 'dart:developer' as dev;

import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/asset_download_cubit/asset_download_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/asset_download_cubit/asset_download_state.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

const _active = {
  AssetDownloadPhase.fetchingReleaseInfo,
  AssetDownloadPhase.downloading,
  AssetDownloadPhase.extracting,
  AssetDownloadPhase.updatingLocalData,
};

/// Image packs on this device: which generations are downloaded, the
/// "Download all" queue, and the one-time onboarding offer.
///
/// Everything goes through the app-wide [AssetDownloadCubit] (one download
/// at a time), so closing the sheet never stops a download, and Settings
/// shows the same progress.
class ImagePacks {
  ImagePacks._();

  static const _offerKey = AppConstants.imageOfferBoolKey;

  /// Generations whose pack finished downloading on this device.
  static final downloaded = ValueNotifier<Set<String>>(const {});

  /// Generations still waiting in a "Download all" run (the running one
  /// included). Empty when no run is going.
  static final queue = ValueNotifier<List<String>>(const []);

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      // 2. Fetch synchronously from GetIt (sl)
      final box = sl<Box>(instanceName: AppConstants.imagePacksBoxName);
      downloaded.value = {for (final k in box.keys) k.toString()};
      _loaded = true;
    } catch (e) {
      dev.log('Image pack record unavailable: $e', name: 'ImagePacks');
    }
  }

  static Future<void> _markDownloaded(String generation) async {
    downloaded.value = {...downloaded.value, generation};
    try {
      // Fetch synchronously
      final box = sl<Box>(instanceName: AppConstants.imagePacksBoxName);
      // Put is still an async operation, so we await it
      await box.put(generation, DateTime.now().toIso8601String());
    } catch (e) {
      dev.log('Could not record pack $generation: $e', name: 'ImagePacks');
    }
  }

  /// True the first time only, on this device. The flag is written before
  /// the sheet opens, so even quitting the app mid-sheet doesn't bring the
  /// offer back.
  static Future<bool> claimOnboardingOffer() async {
    try {
      // Fetch synchronously
      final box = sl<Box>(instanceName: AppConstants.appFlagsBoxName);

      if (box.get(_offerKey) == true) return false;
      await box.put(_offerKey, true);
      return true;
    } catch (e) {
      dev.log('Offer flag unavailable, skipping the offer: $e',
          name: 'ImagePacks');
      return false;
    }
  }

  /// One pack. True when it finished.
  static Future<bool> download(String generation) async {
    final cubit = sl<AssetDownloadCubit>();
    if (_active.contains(cubit.state.phase)) return false;
    await cubit.downloadCompleteAssets(generation);
    final s = cubit.state;
    final ok = s.generation == generation &&
        (s.phase == AssetDownloadPhase.completed ||
            (s.phase != AssetDownloadPhase.failed &&
                !_active.contains(s.phase) &&
                s.progress >= 1));
    if (ok) await _markDownloaded(generation);
    return ok;
  }

  /// Every pack not on the device yet, one after another. A pack that
  /// fails is skipped; the rest still download.
  static Future<void> downloadAll(List<String> generations) async {
    if (queue.value.isNotEmpty) return;
    final todo =
        generations.where((g) => !downloaded.value.contains(g)).toList();
    if (todo.isEmpty) return;
    queue.value = todo;
    final cubit = sl<AssetDownloadCubit>();
    try {
      for (final g in todo) {
        // A single download started from the list: let it finish first.
        while (_active.contains(cubit.state.phase)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        await download(g);
        queue.value = [
          for (final x in queue.value)
            if (x != g) x
        ];
      }
    } finally {
      queue.value = const [];
    }
  }
}

/// Part image packs, per generation, with "Download all".
///
///  ImagePackOfferSheet.offerOnce(context)  // end of onboarding, once
///  ImagePackOfferSheet.show(context)       // Settings › Beyblade Data
///
/// Not on the web: there, part images load from their URLs.
class ImagePackOfferSheet extends StatefulWidget {
  const ImagePackOfferSheet._({required this.onboarding});

  final bool onboarding;

  static Future<void> show(BuildContext context,
      {bool onboarding = false}) async {
    if (kIsWeb) return;
    await ImagePacks.load();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => ImagePackOfferSheet._(onboarding: onboarding),
    );
  }

  /// The onboarding offer: shown the first time only, never again on this
  /// device. Afterwards the packs live in Settings.
  static Future<void> offerOnce(BuildContext context) async {
    if (kIsWeb) return;
    if (!await ImagePacks.claimOnboardingOffer()) return;
    if (!context.mounted) return;
    await show(context, onboarding: true);
  }

  @override
  State<ImagePackOfferSheet> createState() => _ImagePackOfferSheetState();
}

class _ImagePackOfferSheetState extends State<ImagePackOfferSheet> {
  final _cubit = sl<AssetDownloadCubit>();
  late final Future<List<String>> _generations = _loadGenerations();

  /// Generations in the catalog on this device, so the list never offers a
  /// pack for parts the app doesn't have.
  static Future<List<String>> _loadGenerations() async {
    try {
      final repo = sl<BeybladeDataRepo>();
      final lists = await Future.wait([repo.getAllBlades(), repo.getAllBits()]);
      final gens = {
        for (final list in lists)
          for (final p in list) p.hobbyGeneration,
      }..removeWhere((g) => g.trim().isEmpty);
      return gens.toList()..sort();
    } catch (e) {
      dev.log('No generations: $e', name: 'ImagePackOfferSheet');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: BlocBuilder<AssetDownloadCubit, AssetDownloadState>(
          bloc: _cubit,
          builder: (context, state) => ValueListenableBuilder<Set<String>>(
            valueListenable: ImagePacks.downloaded,
            builder: (context, downloaded, _) =>
                ValueListenableBuilder<List<String>>(
              valueListenable: ImagePacks.queue,
              builder: (context, queue, _) {
                final anyActive =
                    _active.contains(state.phase) || queue.isNotEmpty;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                      rc.horizontalPadding, 0, rc.horizontalPadding, rc.md),
                  child: FutureBuilder<List<String>>(
                    future: _generations,
                    builder: (context, snap) {
                      final loading =
                          snap.connectionState != ConnectionState.done;
                      final gens = snap.data ?? const <String>[];
                      final missing =
                          gens.where((g) => !downloaded.contains(g)).toList();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HoloSectionLabel(
                            title: TrTokens.imgPackHead.tr,
                            info: InfoChip(
                              title: TrTokens.imgPackInfoHead.tr,
                              popupIcon: Icons.photo_library_outlined,
                              details: TrTokens.imgPackInfo.tr,
                            ),
                            alignInfoEnd: true,
                          ),
                          SizedBox(height: rc.sm),
                          Text(
                            widget.onboarding
                                ? TrTokens.imgPackIntroOnboarding.tr
                                : TrTokens.imgPackIntroSettings.tr,
                            style: TextStyle(
                                fontSize: rc.body, color: cs.onSurfaceVariant),
                          ),
                          SizedBox(height: rc.md),
                          Flexible(
                            child: loading
                                ? const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(child: BeybladeSpinner()),
                                  )
                                : gens.isEmpty
                                    ? Text(TrTokens.imgPackNoCatalog.tr,
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant))
                                    : _PackGrid(
                                        generations: gens,
                                        state: state,
                                        downloaded: downloaded,
                                        queue: queue,
                                      ),
                          ),
                          SizedBox(height: rc.lg),
                          _Buttons(
                            onboarding: widget.onboarding,
                            anyActive: anyActive,
                            queue: queue,
                            missing: missing,
                            allDone:
                                !loading && gens.isNotEmpty && missing.isEmpty,
                            onDownloadAll: () =>
                                unawaited(ImagePacks.downloadAll(gens)),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One column on phones, two from 520 px.
class _PackGrid extends StatelessWidget {
  const _PackGrid({
    required this.generations,
    required this.state,
    required this.downloaded,
    required this.queue,
  });

  final List<String> generations;
  final AssetDownloadState state;
  final Set<String> downloaded;
  final List<String> queue;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final busy = _active.contains(state.phase) || queue.isNotEmpty;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 520 ? 2 : 1;
        final gap = rc.sm;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final g in generations)
                SizedBox(
                  width: width,
                  child: _PackRow(
                    generation: g,
                    state: state,
                    onDevice: downloaded.contains(g),
                    queued: queue.contains(g),
                    blocked: busy,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.generation,
    required this.state,
    required this.onDevice,
    required this.queued,
    required this.blocked,
  });

  final String generation;
  final AssetDownloadState state;
  final bool onDevice;
  final bool queued;

  /// Something is downloading; the cubit runs one pack at a time.
  final bool blocked;

  String _phaseLabel() => switch (state.phase) {
        AssetDownloadPhase.fetchingReleaseInfo => TrTokens.imgPackPreparing.tr,
        AssetDownloadPhase.downloading =>
          TrTokens.imgPackDownloading.trArgs([(state.progress * 100).round()]),
        AssetDownloadPhase.extracting => TrTokens.imgPackUnpacking.tr,
        AssetDownloadPhase.updatingLocalData => TrTokens.imgPackFinishing.tr,
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final t = HoloTokens.of(context);
    final mine = state.generation == generation;
    final active = mine && _active.contains(state.phase);
    final failed = mine && state.phase == AssetDownloadPhase.failed;

    Widget trailing;
    if (active) {
      trailing =
          const SizedBox(width: 20, height: 20, child: BeybladeSpinner());
    } else if (queued) {
      trailing = HoloPill(
          label: TrTokens.imgPackQueued.tr, color: cs.onSurfaceVariant);
    } else if (onDevice) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HoloPill(
              label: TrTokens.imgPackOnDevice.tr,
              color: t.success,
              icon: Icons.check),
          IconButton(
            tooltip: TrTokens.imgPackDownloadAgain.tr,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: blocked
                ? null
                : () => unawaited(ImagePacks.download(generation)),
          ),
        ],
      );
    } else {
      trailing = HoloActionButton(
        label: failed ? TrTokens.retryTxt.tr : TrTokens.imgPackDownload.tr,
        icon: failed ? Icons.refresh : Icons.download_rounded,
        dense: true,
        variant: HoloButtonVariant.outline,
        onPressed:
            blocked ? null : () => unawaited(ImagePacks.download(generation)),
      );
    }

    return HoloCard(
      padding: EdgeInsets.all(rc.sm * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_outlined, color: cs.onSurfaceVariant),
              SizedBox(width: rc.sm),
              Expanded(
                child: Text(
                  TrTokens.imgPackGeneration.trArgs([generation]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: rc.body, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: rc.sm),
              trailing,
            ],
          ),
          if (active) ...[
            SizedBox(height: rc.sm),
            HoloProgressBar(
                value: state.phase == AssetDownloadPhase.downloading
                    ? state.progress
                    : 1),
            SizedBox(height: rc.xs),
            Text(_phaseLabel(),
                style:
                    TextStyle(fontSize: rc.bodySM, color: cs.onSurfaceVariant)),
          ],
          if (failed && state.errorMessage != null) ...[
            SizedBox(height: rc.xs),
            Text(state.errorMessage!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: rc.bodySM, color: t.danger)),
          ],
        ],
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.onboarding,
    required this.anyActive,
    required this.queue,
    required this.missing,
    required this.allDone,
    required this.onDownloadAll,
  });

  final bool onboarding;
  final bool anyActive;
  final List<String> queue;
  final List<String> missing;
  final bool allDone;
  final VoidCallback onDownloadAll;

  @override
  Widget build(BuildContext context) {
    final t = HoloTokens.of(context);
    final Widget all;
    if (queue.isNotEmpty) {
      all = HoloActionButton(
        label: TrTokens.imgPackAllRunning.trArgs([queue.length]),
        icon: Icons.downloading_rounded,
        variant: HoloButtonVariant.outline,
        expand: true,
        onPressed: null,
      );
    } else if (allDone) {
      all = Center(
        child: HoloPill(
            label: TrTokens.imgPackAllDone.tr,
            color: t.success,
            icon: Icons.check_circle_outline),
      );
    } else {
      all = HoloActionButton(
        label: TrTokens.imgPackDownloadAll.trArgs([missing.length]),
        icon: Icons.download_for_offline_outlined,
        variant: HoloButtonVariant.outline,
        expand: true,
        onPressed: missing.isEmpty || anyActive ? null : onDownloadAll,
      );
    }
    final close = HoloActionButton(
      label: onboarding
          ? (anyActive
              ? TrTokens.imgPackContinueBusy.tr
              : TrTokens.continueTxt.tr)
          : TrTokens.closeTxt.tr,
      icon: onboarding ? Icons.arrow_forward : Icons.close,
      expand: true,
      onPressed: () => Navigator.of(context).pop(),
    );

    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 520
          ? Row(
              children: [
                Expanded(child: all),
                const SizedBox(width: 12),
                Expanded(child: close),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [all, const SizedBox(height: 10), close],
            ),
    );
  }
}
