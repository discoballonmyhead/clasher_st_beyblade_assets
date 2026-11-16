import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:flutter/material.dart';

/// Rebuilds once the part catalog has loaded, so part names never stay on
/// the "Blade #12" fallback.
mixin _CatalogReady<T extends StatefulWidget> on State<T> {
  final PartCatalog catalog = resolvePartCatalog();

  @override
  void initState() {
    super.initState();
    if (!catalog.isReady) {
      catalog.ready().then((_) {
        if (mounted) setState(() {});
      });
    }
  }
}

/// Ban/approve switch, the parts grouped by type, and "Add part".
///
/// The owner keeps the [PartList] and gets every change through [onChanged].
/// Used by the create-tournament page ("New list") and by the Ban & approve
/// lists page in the Beyblade feature, so both behave the same.
class PartListEditor extends StatefulWidget {
  const PartListEditor({
    super.key,
    required this.list,
    required this.onChanged,
  });

  final PartList list;
  final ValueChanged<PartList> onChanged;

  @override
  State<PartListEditor> createState() => _PartListEditorState();
}

class _PartListEditorState extends State<PartListEditor>
    with _CatalogReady<PartListEditor> {
  Future<void> _add() async {
    final list = widget.list;
    final refs = await catalog.pickParts(context, kind: list.kind);
    if (refs.isEmpty || !mounted) return;
    final added = refs.where((r) => !list.contains(r)).toList();
    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(TrTokens.partAlreadyOnListFormat.tr
            .replaceFirst('%s', catalog.nameOf(refs.first))),
      ));
      return;
    }
    var next = list;
    for (final r in added) {
      next = next.withPart(r);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final list = widget.list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSegmented<PartListKind>(
          value: list.kind,
          onChanged: (k) => widget.onChanged(list.copyWith(kind: k)),
          options: [
            HoloOption(PartListKind.ban, TrTokens.banListTxt.tr,
                icon: Icons.block),
            HoloOption(PartListKind.approve, TrTokens.approveListTxt.tr,
                icon: Icons.verified_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Text(list.kind.rule,
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
        SizedBox(height: rc.md),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              TrTokens.noPartsYetTxt.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          )
        else
          // One group per part type, each a sub-category of this list.
          for (final entry in list.parts.entries) ...[
            HoloSubLabel(
              title: catalog.typeLabel(entry.key),
              trailing: Text('${entry.value.length}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in entry.value)
                  InputChip(
                    avatar: catalog.thumbnail(PartRef(entry.key, id)),
                    label: Text(catalog.nameOf(PartRef(entry.key, id))),
                    onDeleted: () => widget
                        .onChanged(list.withoutPart(PartRef(entry.key, id))),
                  ),
              ],
            ),
            SizedBox(height: rc.md),
          ],
        SizedBox(height: rc.sm),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(TrTokens.addPartBtn.tr),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46)),
        ),
      ],
    );
  }
}

/// "Dran Sword, Hells Scythe, 3-60 +4" for a list card. Empty lists show
/// nothing.
class PartListPreview extends StatefulWidget {
  const PartListPreview({super.key, required this.list, this.maxNames = 3});

  final PartList list;
  final int maxNames;

  @override
  State<PartListPreview> createState() => _PartListPreviewState();
}

class _PartListPreviewState extends State<PartListPreview>
    with _CatalogReady<PartListPreview> {
  @override
  Widget build(BuildContext context) {
    final refs = [
      for (final e in widget.list.parts.entries)
        for (final id in e.value) PartRef(e.key, id),
    ];
    if (refs.isEmpty) return const SizedBox.shrink();
    final names = refs.take(widget.maxNames).map(catalog.nameOf).join(', ');
    final more = refs.length - widget.maxNames;
    return Text(
      more > 0 ? '$names +$more' : names,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
