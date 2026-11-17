import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/features/contributions/data/apps_script_contributions_repository.dart';
import 'package:clasher_st/features/contributions/data/catalog_target_search.dart';
import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/data/http_wanted_source.dart';
import 'package:clasher_st/features/contributions/data/image_picker_picture_picker.dart';
import 'package:clasher_st/features/contributions/data/supabase_contributor_identity.dart';
import 'package:clasher_st/features/contributions/data/wanted_target_search.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/domain/usecases.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/contribute_cubit.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/missing_cubits.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Call after BeybladeDependencies.init() (the target search reads the beyblade catalog).
/// Anything already registered (e.g. your own [ContributionsConfig] or [ContributorIdentity]) is kept.
class ContributionsDependencies {
  const ContributionsDependencies._();

  static void init({String appVersion = ''}) {
    if (!sl.isRegistered<ContributionsConfig>()) {
      sl.registerLazySingleton<ContributionsConfig>(() => ContributionsConfig.fromEnvironment(
            appVersion: appVersion,
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
          ));
    }
    if (!sl.isRegistered<ContributorIdentity>()) {
      sl.registerLazySingleton<ContributorIdentity>(
          () => SupabaseContributorIdentity(Supabase.instance.client));
    }
    sl
      ..registerLazySingleton<ContributionsRepository>(() => AppsScriptContributionsRepository(sl()))
      // only entries that are missing something (the wanted list); the whole catalog when the list isn't there
      ..registerLazySingleton<ContributionTargetSearch>(() => WantedTargetSearch(sl(), CatalogTargetSearch(sl())))
      ..registerLazySingleton<ContributionPicturePicker>(() => ImagePickerPicturePicker())
      ..registerLazySingleton(() => SubmitContributionUseCase(sl(), sl()))
      ..registerLazySingleton<WantedSource>(() => HttpWantedSource(sl()))
      ..registerFactoryParam<ContributeCubit, ContributionTarget?, void>(
        (target, _) => ContributeCubit(submit: sl(), search: sl(), picker: sl(), initialTarget: target),
      )
      ..registerFactory<MissingListCubit>(() => MissingListCubit(sl()))
      ..registerFactoryParam<FillMissingCubit, WantedItem, WantedSheet?>(
        (item, sheet) => FillMissingCubit(item: item, sheet: sheet, submit: sl(), picker: sl()),
      );
  }
}
