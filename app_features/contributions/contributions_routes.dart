import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/contribute_cubit.dart';
import 'package:clasher_st/features/contributions/presentation/pages/contribute_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Add [routes] to the app's router (next to the settings routes).
class ContributionsRoutes {
  const ContributionsRoutes._();

  static const contribute = '/settings/contribute';

  /// `extra` may be a [ContributionTarget] to start from (e.g. a "send a picture of this" button on a part page).
  static List<GoRoute> get routes => [
        GoRoute(
          path: contribute,
          builder: (context, state) => BlocProvider(
            create: (_) => sl<ContributeCubit>(
              param1: state.extra is ContributionTarget ? state.extra as ContributionTarget : null,
            )..start(),
            child: const ContributePage(),
          ),
        ),
      ];
}
