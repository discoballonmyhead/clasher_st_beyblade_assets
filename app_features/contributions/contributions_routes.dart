import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/contribute_cubit.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/missing_cubits.dart';
import 'package:clasher_st/features/contributions/presentation/pages/contribute_page.dart';
import 'package:clasher_st/features/contributions/presentation/pages/fill_missing_page.dart';
import 'package:clasher_st/features/contributions/presentation/pages/missing_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Add [routes] to the app's router (next to the settings routes). Nothing else in the app links here except
/// the settings tile, so the feature stays isolated.
class ContributionsRoutes {
  const ContributionsRoutes._();

  /// "Help complete the catalog": the list of what's missing.
  static const contribute = '/settings/contribute';

  /// Free-form: send a picture of anything. `extra` may be a [ContributionTarget] to start from (e.g. a "send a
  /// picture of this" button on a part page).
  static const send = '/settings/contribute/send';

  /// One entry's missing fields. `extra` is `(WantedItem, WantedSheet?)`.
  static const fill = '/settings/contribute/item';

  static List<GoRoute> get routes => [
        GoRoute(
          path: contribute,
          builder: (context, state) => BlocProvider(
            create: (_) => sl<MissingListCubit>()..load(),
            child: const MissingListPage(),
          ),
        ),
        GoRoute(
          path: send,
          builder: (context, state) => BlocProvider(
            create: (_) => sl<ContributeCubit>(
              param1: state.extra is ContributionTarget ? state.extra as ContributionTarget : null,
            )..start(),
            child: const ContributePage(),
          ),
        ),
        GoRoute(
          path: fill,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! (WantedItem, WantedSheet?)) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text('Open an entry from the list of what\'s missing.')),
              );
            }
            return BlocProvider(
              create: (_) => sl<FillMissingCubit>(param1: extra.$1, param2: extra.$2)..start(),
              child: const FillMissingPage(),
            );
          },
        ),
      ];
}
