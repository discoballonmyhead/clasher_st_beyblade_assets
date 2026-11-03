import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/router/route_kit.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/bey_builder_page.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/beyblade_home.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/combo_decks_page.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/detail_page.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/part_lists_page.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/part_search_page.dart';
import 'package:clasher_st/features/beyblade_tcg/presentation/tcg_cards_page.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/build_readiness_cubit/build_readiness_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/quick_add_cubit/quick_add_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/pages/build_readiness_page.dart';
import 'package:clasher_st/features/user_collection/presentation/pages/quick_add_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class BeybladeRoutes {
  BeybladeRoutes._();

  static const String builder = '/beyblade/builder';
  static const String builderName = 'beybladeBuilder';
  static const String assets = '/beyblade/assets';
  static const String assetsName = 'beybladeAssets';
  static const String search = '/beyblade/search';
  static const String combosDecks = '/beyblade/combos-decks';
  static const String detail = '/beyblade/detail';
  static const String inventory = '/beyblade/inventory';
  static const String wishlist = '/beyblade/wishlist';
  static const String analytics = '/beyblade/analytics';
  static const String lent = '/beyblade/lent';
  static const String borrowed = '/beyblade/borrowed';
  static const String backup = '/beyblade/backup';
  static const String collectionAdd = '/beyblade/collection/add';
  static const String buildCheck = '/beyblade/collection/build-check';

  /// Saved ban / approve lists (tournament part rules).
  static const String partLists = '/beyblade/part-lists';

  /// Beyblade TCG cards (separate hobby, same catalog download).
  static const String tcg = '/beyblade/tcg';

  static List<RouteBase> get routes => [
        GoRoute(
          path: builder,
          name: builderName,
          builder: (_, __) => const BeyBuilderPage(),
        ),
        GoRoute(
          path: assets,
          name: assetsName,
          builder: (_, __) => const BeybladeHomePage(),
        ),
        GoRoute(path: search, builder: (_, __) => const PartSearchPage()),
        GoRoute(path: combosDecks, builder: (_, __) => const CombosDecksPage()),
        GoRoute(
          path: detail,
          builder: (context, state) => state.extra is DetailSubject
              ? DetailPage(subject: state.extra as DetailSubject)
              : const LinkProblemPage(),
        ),
        GoRoute(
          path: inventory,
          builder: (_, __) => BlocProvider<InventoryCubit>.value(
            value: sl<InventoryCubit>(),
            child: const UserCollectionPage(),
          ),
        ),
        GoRoute(
          path: collectionAdd,
          builder: (_, __) => MultiBlocProvider(
            providers: [
              BlocProvider<InventoryCubit>.value(value: sl<InventoryCubit>()),
              BlocProvider(create: (_) => sl<QuickAddCubit>()),
            ],
            child: const QuickAddPage(),
          ),
        ),
        GoRoute(
          path: buildCheck,
          builder: (_, __) => MultiBlocProvider(
            providers: [
              BlocProvider<InventoryCubit>.value(value: sl<InventoryCubit>()),
              BlocProvider<WishlistCubit>.value(value: sl<WishlistCubit>()),
              BlocProvider(create: (_) => sl<BuildReadinessCubit>()),
            ],
            child: const BuildReadinessPage(),
          ),
        ),
        GoRoute(path: wishlist, builder: (_, __) => const WishlistPage()),
        GoRoute(
          path: partLists,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<PartListsCubit>()..load(),
            child: const PartListsPage(),
          ),
        ),
        GoRoute(path: tcg, builder: (_, __) => const TcgCardsPage()),
        GoRoute(
          path: analytics,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<CollectionAnalyticsCubit>(),
            child: const CollectionAnalyticsPage(),
          ),
        ),
        GoRoute(
          path: lent,
          builder: (_, __) => const LendBorrowRecordsPage(lending: true),
        ),
        GoRoute(
          path: borrowed,
          builder: (_, __) => const LendBorrowRecordsPage(lending: false),
        ),
        GoRoute(
          path: backup,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<BackupCubit>(),
            child: const BackupPage(),
          ),
        ),
      ];
}
