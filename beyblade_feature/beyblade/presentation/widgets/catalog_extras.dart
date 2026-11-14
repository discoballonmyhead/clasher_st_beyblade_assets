import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

// The optional catalog extras on screen: 3D models (parts and stock combos) and the bladers who use a part.

// ── 3D MODELS ────────────────────────────────────────────────────────────────

/// Where "View in 3D" goes. On Android, Google's Scene Viewer shows a .glb straight from its https URL (no
/// package needed); elsewhere the file itself opens. To show models inside the app instead, swap this for a
/// viewer widget (e.g. model_viewer_plus) fed with the same [url].
Uri model3dViewerUri(String url, {String? title, TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  if (!kIsWeb && p == TargetPlatform.android) {
    return Uri.https('arvr.google.com', '/scene-viewer/1.0', {
      'file': url,
      'mode': '3d_preferred',
      if (title != null) 'title': title,
    });
  }
  return Uri.parse(url);
}

Future<void> open3dModel(BuildContext context, String url,
    {String? title}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ok = await launchUrl(model3dViewerUri(url, title: title),
        mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('no app');
  } catch (_) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open the 3D model.')));
  }
}

/// Shown only when there is a model.
class Model3dButton extends StatelessWidget {
  const Model3dButton({super.key, required this.url, this.title});

  final String? url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    return HoloActionButton(
      label: 'View in 3D',
      icon: Icons.view_in_ar_outlined,
      variant: HoloButtonVariant.outline,
      dense: true,
      onPressed: () => open3dModel(context, url!, title: title),
    );
  }
}

// ── STOCK COMBO ACTIONS ──────────────────────────────────────────────────────

/// "Open in builder" (the combo's parts, ready to save or tweak) and "View in 3D" when it has a model.
class StockComboActions extends StatelessWidget {
  const StockComboActions({super.key, required this.combo, this.builderRoute});

  final StockCombo combo;

  /// The builder's route (BeybladeRoutes.builder); it takes the loadout as `extra`.
  final String? builderRoute;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return Wrap(
      spacing: rc.sm,
      runSpacing: rc.sm,
      children: [
        if (builderRoute != null)
          HoloActionButton(
            label: 'Open in builder',
            icon: Icons.build_outlined,
            variant: HoloButtonVariant.outline,
            dense: true,
            onPressed: () =>
                GoRouter.of(context).push(builderRoute!, extra: combo.loadout),
          ),
        Model3dButton(url: combo.model3dUrl, title: combo.name),
      ],
    );
  }
}

// ── BLADERS ──────────────────────────────────────────────────────────────────

/// "Used in the show by": the bladers linked to a part (BeybladePart.bladerIds). Nothing when there are none.
class BladersSection extends StatelessWidget {
  const BladersSection({super.key, required this.bladers, this.index});

  final List<Blader> bladers;
  final String? index;

  @override
  Widget build(BuildContext context) {
    if (bladers.isEmpty) return const SizedBox.shrink();
    final rc = ResponsiveProvider.config(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(
          title: 'Used in the show by',
          subtitle: bladers.length == 1 ? '1 blader' : '${bladers.length} bladers',
          index: index,
        ),
        SizedBox(height: rc.sm),
        Wrap(
          spacing: rc.sm,
          runSpacing: rc.sm,
          children: [for (final b in bladers) BladerChip(blader: b)],
        ),
      ],
    );
  }
}

/// A blader's small portrait and name; tap for the full-body picture.
class BladerChip extends StatelessWidget {
  const BladerChip({super.key, required this.blader, this.size = 64});

  final Blader blader;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showBladerSheet(context, blader),
      child: SizedBox(
        width: size + 8,
        child: Column(
          children: [
            ClipOval(
              child: PartImageThumb(
                imageUrl: preferredImageSource(
                        blader.minifiedImageUrl, blader.imageUrl) ??
                    preferredImageSource(blader.minifiedFullBodyImageUrl,
                        blader.fullBodyImageUrl),
                size: size,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              blader.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showBladerSheet(BuildContext context, Blader blader) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final tt = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        final full = preferredImageSource(
                blader.minifiedFullBodyImageUrl, blader.fullBodyImageUrl,
                compact: false) ??
            preferredImageSource(blader.minifiedImageUrl, blader.imageUrl,
                compact: false);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (full != null)
                  PartImageThumb(
                    imageUrl: full,
                    size: MediaQuery.sizeOf(context).height * 0.4,
                    scale: 0.95,
                  ),
                const SizedBox(height: 12),
                Text(blader.name, style: tt.titleLarge),
                if (blader.description != null) ...[
                  const SizedBox(height: 6),
                  Text(blader.description!,
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        );
      },
    );
