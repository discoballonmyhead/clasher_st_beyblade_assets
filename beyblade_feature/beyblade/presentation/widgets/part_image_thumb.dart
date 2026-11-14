// =============================================================================
// PART IMAGES + PART-TYPE HELPERS
// -----------------------------------------------------------------------------
// Imports this file needs:
//
//   import 'dart:convert' show base64Decode;
//   import 'package:cached_network_image/cached_network_image.dart';
//   import 'package:flutter/foundation.dart' show kIsWeb;
//   import 'package:flutter/material.dart';
//   import '<path>/local_image_provider.dart';
//   ... your ResponsiveProvider, entities, BeybladeSpinner
//
// REMOVE `import 'dart:io';` — it is what breaks the web build, and nothing
// here references File anymore. Local files go through local_image_provider,
// which stubs itself out on web.
//
// `dev` is no longer used either, so drop that import if this file was its
// only consumer.
// =============================================================================

// ── Source classification ────────────────────────────────────────────────────

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:clasher_st/core/image_provider/local_image_provider_io.dart';
import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isRemoteUrl(String? s) =>
    s != null && (s.startsWith('http://') || s.startsWith('https://'));

bool isDataUri(String? s) => s != null && s.startsWith('data:');

bool isBundledAsset(String? s) => s != null && s.startsWith('assets/');

/// A path written by the asset downloader: not remote, not a data URI, not a
/// bundled asset. On web these can never be read, so they don't count.
bool isDownloadedAsset(String? s) {
  if (s == null || s.isEmpty) return false;
  if (isRemoteUrl(s) || isDataUri(s) || isBundledAsset(s)) return false;
  return supportsLocalFiles;
}

/// The single place that turns a source string into something Flutter can draw.
ImageProvider? beyImageProvider(String? source) {
  final s = source?.trim();
  if (s == null || s.isEmpty) return null;

  if (isDataUri(s)) {
    final comma = s.indexOf(',');
    if (comma == -1) return null;
    try {
      return MemoryImage(base64Decode(s.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }

  if (isRemoteUrl(s)) return CachedNetworkImageProvider(s);
  if (isBundledAsset(s)) return AssetImage(s);

  // Downloaded file. Null on web, where the caller falls back.
  return localFileImage(s);
}

// ── Which of the two images to draw ──────────────────────────────────────────

/// The rule, once: a downloaded file always beats a remote URL, whatever its
/// size, because the user already paid to download it. Only after that does
/// size preference apply.
///
/// [compact] is for lists and grids; pass false for a hero or detail view where
/// the full-resolution image is worth the bytes.
String? preferredImageSource(String? minified, String? full,
    {bool compact = true}) {
  if (isDownloadedAsset(minified)) return minified;
  if (isDownloadedAsset(full)) return full;

  // On web a local path is unusable, so prefer whichever of the two is remote.
  if (kIsWeb) {
    final remoteMini = isRemoteUrl(minified) ? minified : null;
    final remoteFull = isRemoteUrl(full) ? full : null;
    return compact ? (remoteMini ?? remoteFull) : (remoteFull ?? remoteMini);
  }

  return compact ? (minified ?? full) : (full ?? minified);
}

/// Which image a context should use for a part.
String? preferredThumbUrl(BeybladePart? part,
        {bool compact = true}) =>
    part == null
        ? null
        : preferredImageSource(part.minifiedImageUrl, part.imageUrl,
            compact: compact);

/// Products carry the same pair under different names, and had the same bug:
/// `minifiedBoxImageUrl ?? boxImageUrl` picks a remote minified box shot over a
/// downloaded full-size one.
String? preferredProductThumbUrl(Product? product, {bool compact = true}) =>
    product == null
        ? null
        : preferredImageSource(product.minifiedBoxImageUrl, product.boxImageUrl,
            compact: compact);

/// Accessories only have the one image, so there is nothing to choose between —
/// this exists so call sites don't have to special-case the third type.
String? preferredAccessoryThumbUrl(Accessory? accessory) => accessory?.imageUrl;

/// Single source of truth for "how should this part type's image be
/// scaled" -- every PartImageThumb call site should derive [scale] from
/// this instead of hardcoding a number, so a rule like "bits render
/// small" can't silently apply in one place and be missed in another.
double imageScaleFor(BeybladePart? part) => part is Bit
    ? 0.6
    : part is Ratchet
        ? 0.8
        : 1.0;

// ── The thumb ────────────────────────────────────────────────────────────────

/// Square product-photo tile. Same constructor as the original, so every
/// existing call site keeps working.
class PartImageThumb extends StatelessWidget {
  const PartImageThumb({
    super.key,
    required this.imageUrl,
    this.size = 56,
    this.scale = 1.0,
    this.borderRadius,
    this.background,
  });

  final String? imageUrl;
  final double size;

  /// Shrinks the artwork inside its box — see [imageScaleFor]. Below 1 the
  /// image also switches to contain, since the point is to see the whole part.
  final double scale;

  final BorderRadius? borderRadius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final radius = borderRadius ?? BorderRadius.circular(rc.borderRadius);
    final source = beyImageProvider(imageUrl);

    if (source == null) {
      return _Placeholder(size: size, radius: radius, background: background);
    }

    // Decode at the size it's drawn, not at the file's full resolution:
    // a picker lists hundreds of parts, and full-size decodes there were
    // the jank and the memory spikes. Same provider + width = same cache
    // key, so a repeat thumb is still a cache hit.
    final px = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    final provider = ResizeImage.resizeIfNeeded(px, null, source);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: background ?? cs.surfaceContainerHighest,
        child: _scaled(
          Image(
            image: provider,
            fit: scale < 1.0 ? BoxFit.contain : BoxFit.cover,
            gaplessPlayback: true,

            // Local files and bundled assets resolve synchronously, so only
            // the network path gets a fade — no flicker on a fast scroll.
            frameBuilder: (context, child, frame, synchronous) {
              if (synchronous) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: frame == null
                    ? _Placeholder(
                        size: size, radius: radius, background: background)
                    : child,
              );
            },

            errorBuilder: (context, error, stack) => _Placeholder(
                size: size, radius: radius, background: background),
          ),
        ),
      ),
    );
  }

  Widget _scaled(Widget child) => scale < 1.0
      ? Center(
          child: FractionallySizedBox(
              widthFactor: scale, heightFactor: scale, child: child))
      : child;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.radius,
    this.background,
  });

  final double size;
  final BorderRadius radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: size * 0.34,
        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}

// ── Part-type lookups ────────────────────────────────────────────────────────

/// The human-readable label for a part-type short key -- shared here
/// (not duplicated per-file) so detail_page.dart and wishlist_page.dart
/// can't drift into showing different labels for the same key.
String displayLabelForPartType(String partTypeKey) => switch (partTypeKey) {
      'blades' => 'Blade',
      'ratchets' => 'Ratchet',
      'bits' => 'Bit',
      'lockChips' => 'Lock Chip',
      'overBlades' => 'Over Blade',
      'metalBlades' => 'Metal Blade',
      'mainBlades' => 'Main Blade',
      'assistBlades' => 'Assist Blade',
      // Not sheet part-types, but the collection groups items by these
      // same keys, so they belong in the one label function rather than
      // in a second lookup that could disagree with this one.
      'products' => 'Product',
      'accessories' => 'Accessory',
      _ => partTypeKey,
    };

/// The sheet short key for a resolved BeybladePart instance -- needed
/// anywhere a part must be referenced by (type, dataId) rather than
/// passed as a live object.
String partTypeKeyFor(BeybladePart part) => switch (part) {
      Blade _ => 'blades',
      Ratchet _ => 'ratchets',
      Bit _ => 'bits',
      LockChip _ => 'lockChips',
      OverBlade _ => 'overBlades',
      MetalBlade _ => 'metalBlades',
      MainBlade _ => 'mainBlades',
      AssistBlade _ => 'assistBlades',
      _ => 'unknown',
    };

/// Icon for a collection group key. Lives beside displayLabelForPartType
/// so the icon and the label for a given key can't drift apart across
/// the home summary, the collection grid and the filter sheet.
IconData iconForGroupKey(String groupKey) => switch (groupKey) {
      'blades' => Icons.change_history,
      'ratchets' => Icons.settings,
      'bits' => Icons.circle_outlined,
      'lockChips' => Icons.lock_outline,
      'overBlades' => Icons.layers_outlined,
      'metalBlades' => Icons.layers,
      'mainBlades' => Icons.hexagon_outlined,
      'assistBlades' => Icons.support_outlined,
      'products' => Icons.inventory_2_outlined,
      'accessories' => Icons.category_outlined,
      _ => Icons.help_outline,
    };
