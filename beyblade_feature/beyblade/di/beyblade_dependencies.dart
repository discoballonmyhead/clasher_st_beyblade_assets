import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/security/app_env.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_cat_remdsrc.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_extras_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/combo_decks_remote.dart';
import 'package:clasher_st/features/beyblade/data/repositories/bey_data_repo_impl.dart';
import 'package:clasher_st/features/beyblade/data/repositories/combo_decks_repo_impl.dart';
import 'package:clasher_st/features/beyblade/domain/engines/beyblade_stats_calculator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/asset_download_cubit/asset_download_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/combo_cubit/combo_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/combo_decks_paged_cubit/combo_decks_paged_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/deck_cubit/deck_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/deck_slot_cubit/beyblade_deck_slots_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/part_search_cubit/part_search_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/part_lists/beyblade_part_catalog.dart';
import 'package:clasher_st/features/beyblade/utils/catalog_randomizer.dart';
import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BeybladeDependencies {
  const BeybladeDependencies._();

  static void init() {
    // ══ BEYBLADE CATALOG ═════════════════════════════════════════════════

    sl.registerLazySingleton<BeybladeDataLocalDatasource>(
      () => BeybladeDataLocalDatasourceImpl(),
    );

    // Stock combos and bladers: their own Hive box, opened on first use.
    sl.registerLazySingleton<BeybladeExtrasLocalDataSource>(
      () => HiveBeybladeExtrasLocalDataSource(),
    );

    sl.registerLazySingleton<BeybladeDataRepo>(
      () => BeyDataRepoImpl(sl(), sl()),
    );

    // Combos & Decks page and the combo picker: paged reads (SQL 82).
    sl.registerLazySingleton<CombosDecksRemoteDataSource>(
      () => CombosDecksRemoteDataSourceImpl(Supabase.instance.client),
    );
    sl.registerLazySingleton<CombosDecksRepository>(
      () => CombosDecksRepositoryImpl(remote: sl(), local: sl(), data: sl()),
    );
    sl.registerLazySingleton(
        () => PartListsRepository(Supabase.instance.client));

    // The real parts picker for ban / approve lists. Without it
    // resolvePartCatalog() falls back to typing a part type and data id.
    sl.registerLazySingleton<PartCatalog>(() => BeybladePartCatalog(sl()));

    // Card game catalog (hobby "Beyblade TCG"), filled from catalog.zip.
    sl.registerLazySingleton<TcgCatalog>(() => TcgCatalog(HiveTcgStore()));

    // Checks for and downloads newer catalog releases. Works signed out:
    // the manifest RPC is granted to anon, so the splash can check on a
    // first launch before anyone has logged in.
    sl.registerLazySingleton<BeybladeCatalogRemoteDataSource>(
      () => BeybladeCatalogRemoteDataSourceImpl(
        supabaseClient: sl<SupabaseClient>(),
      ),
    );

    sl.registerLazySingleton<BeybladeStatsCalculator>(
      () => const BeybladeStatsCalculator(),
    );

    // ── Catalog use cases ──
    sl.registerLazySingleton<ResolveBeybladeUseCase>(
      () => ResolveBeybladeUseCase(sl(), sl()),
    );
    sl.registerLazySingleton<SearchBeybladePartsUseCase>(
      () => SearchBeybladePartsUseCase(sl()),
    );
    sl.registerLazySingleton<SyncBeybladeDataUseCase>(
      () => SyncBeybladeDataUseCase(sl()),
    );
    sl.registerLazySingleton<ManageCombosUseCase>(
      () => ManageCombosUseCase(sl()),
    );
    sl.registerLazySingleton<ManageDecksUseCase>(
      () => ManageDecksUseCase(sl()),
    );
    sl.registerLazySingleton<ManageDeckSlotsUseCase>(
      () => ManageDeckSlotsUseCase(sl()),
    );
    sl.registerLazySingleton<GetProductDetailsUseCase>(
      () => GetProductDetailsUseCase(sl()),
    );
    sl.registerLazySingleton<GetPartDetailsUseCase>(
      () => GetPartDetailsUseCase(sl()),
    );
    sl.registerLazySingleton<GetBladersUseCase>(
      () => GetBladersUseCase(sl()),
    );
    // Random builds from the catalog. Holds no part data itself (each
    // screen opens its own session), so it never serves a stale catalog.
    sl.registerLazySingleton<CatalogRandomizer>(
      () => CatalogRandomizer(sl()),
    );

    // ── Asset download (services come from core DI) ──
    sl.registerLazySingleton<DownloadGenerationAssetsUseCase>(
      () => DownloadGenerationAssetsUseCase(
        downloadService: sl(),
        dataRepository: sl(),
        tracker: sl(),
      ),
    );
    sl.registerLazySingleton<ResumeInFlightDownloadsUseCase>(
      () => ResumeInFlightDownloadsUseCase(
        downloadService: sl(),
        dataRepository: sl(),
        tracker: sl(),
      ),
    );

    // ══ CUBITS ═══════════════════════════════════════════════════════════
    // Singleton, started from the splash page via startup().
    sl.registerLazySingleton<BeybladeSyncCubit>(
      () => BeybladeSyncCubit(
        syncUseCase: sl(),
        catalogRemote: sl(),
        tcgCatalog: sl<TcgCatalog>(),
      ),
    );
    // Page-scoped: no cross-page state to keep in sync.
    sl.registerFactory<PartSearchCubit>(() => PartSearchCubit(sl()));
    sl.registerFactory<BeyBuilderCubit>(() => BeyBuilderCubit(sl()));
    sl.registerFactory<DeckSlotsCubit>(() => DeckSlotsCubit(sl(), sl()));
    sl.registerFactory<CombosCubit>(() => CombosCubit(sl()));
    sl.registerFactory<DecksCubit>(() => DecksCubit(sl()));
    sl.registerFactory<CombosPageCubit>(() => CombosPageCubit(sl()));
    sl.registerFactory<DecksPageCubit>(() => DecksPageCubit(sl()));
    sl.registerFactory<ComboPickerCubit>(() => ComboPickerCubit(sl()));

    // BackupCubit moved to user_collection/di/di.dart.
    sl.registerLazySingleton<AssetDownloadCubit>(
      () => AssetDownloadCubit(
        downloadUseCase: sl(),
        githubReleaseTag: AppEnv.githubReleaseTag,
      ),
    );

    sl.registerFactory(() => PartListsCubit(sl()));
  }
}
