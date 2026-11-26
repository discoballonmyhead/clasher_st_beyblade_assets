// Tournament kits (formerly "Ban & approve lists"), managed in the Beyblade
// feature.
//
// The host's saved kits: the same ones the create-tournament page offers.
// Part rules (ban list, allowed parts) limit the decks players bring;
// organiser kits (parts pool, deck kit) are what the organiser hands out
// in formats like Mirror Match. Uses PartListsCubit / PartListsRepository.
//
// Reached from the Bey Station "Manage" grid and from "Manage kits" on the
// create-tournament page (route BeybladeRoutes.partLists). Creating and
// editing a kit is its own route: PartListEditPage.

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class PartListsPage extends StatelessWidget {
  const PartListsPage({super.key});

  /// The edit page loads the kit by id itself; nothing is passed along
  /// and nothing comes back (this page updates from the repository).
  void _open(BuildContext context, PartList list) {
    final id = list.id;
    context.push(id == null
        ? BeybladeRoutes.partListNewOf(list.kind)
        : BeybladeRoutes.partListEdit(id));
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;

    return ResponsiveScaffold(
      maxWidth: rc.maxContentWidth,
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(TrTokens.kitsPageTitle.tr)),
      body: BlocBuilder<PartListsCubit, PartListsState>(
        builder: (context, state) {
          if (state.loading && state.lists.isEmpty) {
            return const Center(child: BeybladeSpinner());
          }
          final rules = state.lists.where((l) => l.kind.isPartRule).toList();
          final kits = state.lists.where((l) => l.kind.isOrganizerKit).toList();
          return RefreshIndicator(
            onRefresh: () => context.read<PartListsCubit>().load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  rc.horizontalPadding, rc.md, rc.horizontalPadding, rc.lg),
              children: [
                Text(
                  TrTokens.kitsPageIntro.tr,
                  style: TextStyle(
                      fontSize: rc.bodySM,
                      height: 1.4,
                      color: cs.onSurfaceVariant),
                ),
                SizedBox(height: rc.md),
                HoloActionRail(
                  actions: [
                    for (final k in PartListKind.values)
                      HoloRailAction(
                        label: k.shortLabel,
                        icon: k.icon,
                        tint: kitKindColor(context, k),
                        onTap: () => _open(context, PartList(kind: k)),
                      ),
                  ],
                ),
                if (state.error != null) ...[
                  SizedBox(height: rc.md),
                  HoloCard(
                    borderColor: HoloTokens.of(context).danger,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(state.error!,
                              style:
                                  TextStyle(fontSize: 13, color: cs.onSurface)),
                        ),
                        HoloActionButton(
                          label: TrTokens.retryTxt.tr,
                          dense: true,
                          variant: HoloButtonVariant.outline,
                          onPressed: () =>
                              context.read<PartListsCubit>().load(),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: rc.lg),
                HoloSectionLabel(
                  title: TrTokens.partRulesTitle.tr,
                  subtitle: TrTokens.kitsRulesSubtitle.tr,
                  info: rules.isEmpty
                      ? null
                      : HoloPill(label: '${rules.length}', color: cs.primary),
                ),
                SizedBox(height: rc.sm),
                if (rules.isEmpty)
                  _empty(
                      context,
                      Icons.rule_outlined,
                      TrTokens.noSavedListsYetTxt.tr,
                      TrTokens.kitsRulesEmpty.tr)
                else
                  for (final list in rules)
                    KitCard(list: list, onTap: () => _open(context, list)),
                SizedBox(height: rc.lg),
                HoloSectionLabel(
                  title: TrTokens.kitsOrganiserTitle.tr,
                  subtitle: TrTokens.kitsOrganiserSubtitle.tr,
                  info: kits.isEmpty
                      ? null
                      : HoloPill(label: '${kits.length}', color: cs.primary),
                ),
                SizedBox(height: rc.sm),
                if (kits.isEmpty)
                  _empty(
                      context,
                      Icons.style_outlined,
                      TrTokens.kitsOrganiserEmptyTitle.tr,
                      TrTokens.kitsOrganiserEmptyMsg.tr)
                else
                  for (final list in kits)
                    KitCard(list: list, onTap: () => _open(context, list)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String body) {
    final cs = Theme.of(context).colorScheme;
    return HoloCard(
      wash: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryText(cs)),
          const SizedBox(width: 12),
          Expanded(child: HoloSubLabel(title: title, subtitle: body)),
        ],
      ),
    );
  }
}

/// A saved kit in a list: kind icon, name, kind tag, size and a preview.
/// [selected] / [trailing] are for pickers (the create-tournament page).
class KitCard extends StatelessWidget {
  const KitCard({
    super.key,
    required this.list,
    this.onTap,
    this.selected = false,
    this.trailing,
  });

  final PartList list;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = kitKindColor(context, list.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HoloCard(
        onTap: onTap,
        highlight: selected,
        wash: selected,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: ChamferBorder.tab(
                    cut: 10,
                    side: BorderSide(color: tint.withValues(alpha: 0.5))),
              ),
              child: Icon(list.kind.icon, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    list.name.isEmpty ? list.kind.label : list.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      HoloPill(label: list.kind.shortLabel, color: tint),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          list.sizeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  PartListPreview(list: list),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
