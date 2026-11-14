import 'dart:developer' as dev;

import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class ResolvedBeyBuilder extends StatefulWidget {
  const ResolvedBeyBuilder({
    super.key,
    required this.loadout,
    required this.builder,
    this.loading,
    this.failed,
  });

  final BeybladeLoadout loadout;
  final Widget Function(BuildContext context, Beyblade beyblade) builder;
  final WidgetBuilder? loading;
  final WidgetBuilder? failed;

  @override
  State<ResolvedBeyBuilder> createState() => _ResolvedBeyBuilderState();
}

class _ResolvedBeyBuilderState extends State<ResolvedBeyBuilder> {
  static const _logName = 'ResolvedBeyBuilder';
  late Future<Beyblade?> _future;

  @override
  void initState() {
    super.initState();
    dev.log('initState - Resolving loadout', name: _logName);
    _future = GetIt.instance<ResolveBeybladeUseCase>()(widget.loadout);
  }

  @override
  void didUpdateWidget(covariant ResolvedBeyBuilder old) {
    super.didUpdateWidget(old);
    if (old.loadout != widget.loadout) {
      dev.log('didUpdateWidget - Loadout changed, resolving again',
          name: _logName);
      _future = GetIt.instance<ResolveBeybladeUseCase>()(widget.loadout);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Beyblade?>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return widget.loading?.call(context) ??
              const SizedBox(width: 24, height: 24, child: BeybladeSpinner());
        }
        final beyblade = snapshot.data;
        if (beyblade == null) {
          dev.log('Build failed - Beyblade resolved to null', name: _logName);
          return widget.failed?.call(context) ??
              const Icon(Icons.help_outline, size: 20);
        }
        return widget.builder(context, beyblade);
      },
    );
  }
}

class ResolvedBeyChip extends StatelessWidget {
  const ResolvedBeyChip(
      {super.key, required this.loadout, this.selected = false, this.onTap});

  final BeybladeLoadout loadout;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ResolvedBeyBuilder(
      loadout: loadout,
      builder: (context, beyblade) {
        final leadPart = beyblade.stackedParts.first;
        return InkWell(
          onTap: () {
            if (onTap != null) {
              dev.log(
                  'ResolvedBeyChip tapped for: ${beyblade.nomenclatureName}',
                  name: 'ResolvedBeyChip');
              onTap!();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color:
                  selected ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border:
                  selected ? Border.all(color: cs.primary, width: 1.6) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: PartImageThumb(
                      imageUrl: preferredThumbUrl(leadPart),
                      size: 24,
                      scale: imageScaleFor(leadPart)),
                ),
                const SizedBox(width: 6),
                Text(
                  beyblade.stackedParts.map((p) => p.name).join(' + '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected ? cs.primary : cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
      loading: (_) => const SizedBox(
          width: 60,
          height: 24,
          child: Center(
              child:
                  SizedBox(width: 14, height: 14, child: BeybladeSpinner()))),
      failed: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
        child: Text('Unavailable',
            style: TextStyle(fontSize: 11, color: cs.onErrorContainer)),
      ),
    );
  }
}

class ResolvedBeyNameChip extends StatelessWidget {
  const ResolvedBeyNameChip(
      {super.key,
      required this.loadout,
      this.selected = false,
      this.onTap,
      this.style});

  final BeybladeLoadout loadout;
  final bool selected;
  final VoidCallback? onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ResolvedBeyBuilder(
      loadout: loadout,
      builder: (context, beyblade) => InkWell(
        onTap: () {
          if (onTap != null) {
            dev.log(
                'ResolvedBeyNameChip tapped for: ${beyblade.nomenclatureName}',
                name: 'ResolvedBeyNameChip');
            onTap!();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: selected ? Border.all(color: cs.primary, width: 1.6) : null,
          ),
          child: Text(
            beyblade.nomenclatureName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style ??
                TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
      loading: (_) => const SizedBox(
          width: 50,
          height: 22,
          child: Center(
              child:
                  SizedBox(width: 12, height: 12, child: BeybladeSpinner()))),
      failed: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
        child: Text('Unavailable',
            style: TextStyle(fontSize: 11, color: cs.onErrorContainer)),
      ),
    );
  }
}
