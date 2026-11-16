import 'dart:async';

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/combo_decks_paged_cubit/combo_decks_paged_cubit.dart';
import 'package:flutter/material.dart';

/// Search field + the phone-copy note + a paged list that loads the next
/// page as its end comes into view. Pull to refresh reloads from the top.
/// Used by both tabs of the Combos & Decks page and by the combo picker.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.state,
    required this.searchHint,
    required this.onSearch,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.empty,
    this.header,
    this.separator = 12,
  });

  final PagedState<T> state;
  final String searchHint;
  final ValueChanged<String> onSearch;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Shown when there's nothing at all (no search typed).
  final Widget empty;

  /// Extra widget between the search field and the list (the picker's
  /// selected chips).
  final Widget? header;
  final double separator;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  late final TextEditingController _search =
      TextEditingController(text: widget.state.query);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) widget.onSearch(text);
    });
    setState(() {}); // show / hide the clear button
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.state;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: TrTokens.clearTxt.tr,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        if (s.fromDevice)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Icon(Icons.cloud_off_outlined,
                  size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(TrTokens.savedOnPhoneNote.tr,
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
        if (widget.header != null) widget.header!,
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final s = widget.state;
    if (s.loading && s.items.isEmpty) {
      return const Center(child: BeybladeSpinner());
    }
    if (s.failed && s.items.isEmpty) {
      return _Retry(
          text: TrTokens.listLoadFailedTxt.tr, onRetry: widget.onRefresh);
    }
    if (s.loaded && s.items.isEmpty) {
      if (s.query.isEmpty) return widget.empty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            TrTokens.noMatchesForTxt.trParams({'query': s.query}),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        itemCount: s.items.length + 1,
        separatorBuilder: (_, __) => SizedBox(height: widget.separator),
        itemBuilder: (context, i) {
          if (i < s.items.length) {
            return widget.itemBuilder(context, s.items[i]);
          }
          return _footer(context);
        },
      ),
    );
  }

  /// Built only when the end of the list is about to show, which is when
  /// the next page should load.
  Widget _footer(BuildContext context) {
    final s = widget.state;
    if (s.moreFailed) {
      return _Retry(
          text: TrTokens.loadMoreFailedTxt.tr,
          onRetry: widget.onLoadMore,
          compact: true);
    }
    if (s.hasMore) {
      if (!s.loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLoadMore();
        });
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _Retry extends StatelessWidget {
  const _Retry(
      {required this.text, required this.onRetry, this.compact = false});

  final String text;
  final Future<void> Function() onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        HoloActionButton(
          label: TrTokens.retryTxt.tr,
          icon: Icons.refresh,
          variant: HoloButtonVariant.tonal,
          onPressed: () => onRetry(),
        ),
      ],
    );
    if (compact) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12), child: content);
    }
    return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: content));
  }
}
