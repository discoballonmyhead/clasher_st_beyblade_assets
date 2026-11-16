import 'dart:async';

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_extras.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_state.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/part_search_cubit/part_search_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/detail_page.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

// ── PART SEARCH ──────────────────────────────────────────────────────────────

class PartSearchPage extends StatelessWidget {
  const PartSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return ResponsiveScaffold(
      maxWidth: rc.maxContentWidth,
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Search Parts')),
      body: BlocConsumer<BeybladeSyncCubit, BeybladeSyncState>(
        listener: (context, syncState) {
          // Re-run whatever was typed the moment the database is ready,
          // so a first-launch search doesn't sit on "No matches".
          if (syncState is SyncFinished || syncState is SyncReady) {
            context.read<PartSearchCubit>().refresh();
          }
        },
        builder: (context, syncState) {
          if (syncState is SyncRunning) {
            return const _SearchMessage(
              icon: null,
              loading: true,
              text: 'Building parts database…',
            );
          }

          if (syncState is SyncError) {
            return _SearchMessage(
              icon: Icons.error_outline,
              isError: true,
              text: 'Failed to load the parts database.',
              action: OutlinedButton(
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(180, 46)),
                onPressed: () =>
                    context.read<BeybladeSyncCubit>().loadBundledMetadata(),
                child: Text(TrTokens.retryTxt.tr),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                rc.horizontalPadding, rc.md, rc.horizontalPadding, rc.md),
            child: Column(
              children: [
                const _SearchField(),
                const SizedBox(height: 18),
                const Expanded(child: _SearchResults()),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField();

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  Timer? _debounce;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _run(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      context.read<PartSearchCubit>().query(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);

    return TextField(
      controller: _controller,
      // autofocus only where a keyboard is the expected input. On desktop it
      // is; on a phone it covers half the screen before the user has decided
      // they want to type.
      autofocus: !rc.deviceInfo.isMobile,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by name or code…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  _run('');
                  setState(() {});
                },
              ),
      ),
      onChanged: (v) {
        _run(v);
        setState(() {}); // just for the clear button
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocBuilder<PartSearchCubit, PartSearchState>(
      builder: (context, state) {
        return RefreshIndicator(
          color: cs.primary,
          onRefresh: () => context.read<PartSearchCubit>().refresh(),
          child: switch (state) {
            PartSearchEmpty() => const _SearchMessage(
                icon: Icons.search,
                text: 'Type to search parts',
              ),
            PartSearchLoading() => const _SearchMessage(loading: true),
            PartSearchError(:final message) => _SearchMessage(
                icon: Icons.error_outline,
                isError: true,
                text: 'Error: $message',
              ),
            PartSearchResults(:final results) => results.isEmpty
                ? const _SearchMessage(
                    icon: Icons.search_off, text: 'No matches')
                : _ResultsBody(results: results),
          },
        );
      },
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.results});
  final List<BeybladePart> results;

  void _open(BuildContext context, BeybladePart part) {
    // partTypeKeyFor derives the sheet key from the runtime type, so the
    // search page never has to carry it alongside each result.
    context.push(
      BeybladeRoutes.detail,
      extra: PartDetailSubject(part, partTypeKeyFor(part)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);

    // A phone reads faster as rows; anything wider wastes most of the line
    // length on a row and reads better as cards.
    if (rc.deviceInfo.isMobile) {
      final cs = Theme.of(context).colorScheme;
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (context, i) => PartListTile(
          part: results[i],
          onTap: () => _open(context, results[i]),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding, rc.xs, rc.horizontalPadding, rc.xxl),
      children: [
        AdaptiveGrid(
          minTileWidth: 210,
          children: [
            for (final part in results)
              _PartResultCard(part: part, onTap: () => _open(context, part)),
          ],
        ),
      ],
    );
  }
}

class _PartResultCard extends StatelessWidget {
  const _PartResultCard({required this.part, required this.onTap});

  final BeybladePart part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // preferredThumbUrl now prefers a downloaded asset over any
              // remote one, so a synced library renders instantly offline.
              Center(
                child: PartImageThumb(
                  imageUrl: preferredThumbUrl(part),
                  size: 96,
                  scale: imageScaleFor(part),
                ),
              ),
              const SizedBox(height: 10),
              Text(part.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${part.code} · ${part.mass}g',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              LegalityBadge(legality: part.legality),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every state renders as a scrollable so RefreshIndicator's pull gesture
/// keeps working even when there's no list on screen.
class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    this.icon,
    this.text,
    this.loading = false,
    this.isError = false,
    this.action,
  });

  final IconData? icon;
  final String? text;
  final bool loading;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(rc.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const BeybladeSpinner()
                    else if (icon != null)
                      Icon(icon,
                          size: 40,
                          color: isError
                              ? cs.error
                              : cs.onSurfaceVariant.withValues(alpha: 0.55)),
                    if (text != null) ...[
                      SizedBox(height: rc.sm),
                      Text(
                        text!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: isError ? cs.error : cs.onSurfaceVariant),
                      ),
                    ],
                    if (action != null) ...[
                      SizedBox(height: rc.md),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
