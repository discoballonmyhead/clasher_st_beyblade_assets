import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/missing_data/data/datasources/engine_data_source.dart';
import '../../features/missing_data/data/repositories/missing_data_repository_impl.dart';
import '../../features/missing_data/domain/repositories/missing_data_repository.dart';
import '../../features/missing_data/domain/usecases/fill_usecases.dart';
import '../../features/missing_data/domain/usecases/row_usecases.dart';
import '../../features/missing_data/domain/usecases/sheet_usecases.dart';
import '../../features/missing_data/domain/usecases/structure_usecases.dart';
import '../../features/missing_data/domain/usecases/workbook_usecases.dart';
import '../../features/missing_data/presentation/cubits/autofill/autofill_cubit.dart';
import '../../features/missing_data/presentation/cubits/row_editor/row_editor_cubit.dart';
import '../../features/missing_data/presentation/cubits/sheet/sheet_cubit.dart';
import '../../features/missing_data/domain/usecases/row_lifecycle_usecases.dart';
import '../../features/missing_data/presentation/cubits/id_check/id_check_cubit.dart';
import '../../features/missing_data/presentation/cubits/recycle_bin/recycle_bin_cubit.dart';
import '../../features/missing_data/presentation/cubits/structure/structure_cubit.dart';
import '../../features/missing_data/presentation/cubits/wiki/wiki_cubit.dart';
import '../../features/missing_data/presentation/cubits/workbook/workbook_cubit.dart';
import '../../features/settings/presentation/cubit/settings_cubit.dart';
import '../../features/translations/data/datasources/translation_data_source.dart';
import '../../features/translations/data/repositories/translation_repository_impl.dart';
import '../../features/translations/data/translation_project_store.dart';
import '../../features/translations/domain/repositories/translation_repository.dart';
import '../../features/translations/presentation/cubits/translation_cubit.dart';
import '../bridge/engine_bridge.dart';
import '../services/data_change_notifier.dart';
import '../services/file_picker_service.dart';
import '../services/unsaved_work.dart';
import '../settings/app_settings.dart';

/// The service locator. Everything is registered here and nowhere else.
final sl = GetIt.instance;

/// Name of the EngineBridge that runs translation_tool.py.
const translationsEngine = 'translations';

Future<void> initDependencies({
  SharedPreferences? prefs,
  FilePickerService? picker,
  MissingDataRepository? repository,
  TranslationRepository? translationRepository,
}) async {
  // ── core ──
  sl.registerLazySingleton<AppSettings>(() => AppSettings(prefs!));
  sl.registerLazySingleton<EngineBridge>(
    EngineBridge.new,
    dispose: (b) => b.dispose(),
  );
  sl.registerLazySingleton<DataChangeNotifier>(
    DataChangeNotifier.new,
    dispose: (n) => n.dispose(),
  );
  sl.registerLazySingleton<UnsavedWork>(UnsavedWork.new);
  // the translation engine runs as its own process (translation_tool.py)
  sl.registerLazySingleton<EngineBridge>(
    EngineBridge.new,
    instanceName: translationsEngine,
    dispose: (b) => b.dispose(),
  );
  sl.registerLazySingleton<FilePickerService>(
    () => picker ?? NativeFilePickerService(),
  );

  // ── data ──
  sl.registerLazySingleton<EngineDataSource>(
    () => EngineDataSource(sl(), sl()),
  );
  sl.registerLazySingleton<MissingDataRepository>(
    () => repository ?? MissingDataRepositoryImpl(sl()),
  );

  // ── domain ──
  sl
    ..registerLazySingleton(() => OpenWorkbook(sl()))
    ..registerLazySingleton(() => GetWorkbookSummary(sl()))
    ..registerLazySingleton(() => SaveWorkbook(sl()))
    ..registerLazySingleton(() => UndoLastChange(sl()))
    ..registerLazySingleton(() => GetRecentEdits(sl()))
    ..registerLazySingleton(() => RecoverUnsaved(sl()))
    ..registerLazySingleton(() => DiscardUnsaved(sl()))
    ..registerLazySingleton(() => AnalyzeSheet(sl()))
    ..registerLazySingleton(() => ListRows(sl()))
    ..registerLazySingleton(() => GetRow(sl()))
    ..registerLazySingleton(() => UpdateRow(sl()))
    ..registerLazySingleton(() => SetRowImage(sl()))
    ..registerLazySingleton(() => GetParentImage(sl()))
    ..registerLazySingleton(() => GetFillProposals(sl()))
    ..registerLazySingleton(() => ApplyFillProposals(sl()))
    ..registerLazySingleton(() => FillFromWiki(sl()))
    ..registerLazySingleton(() => AddColumn(sl()))
    ..registerLazySingleton(() => AddRow(sl()))
    ..registerLazySingleton(() => GetColumns(sl()))
    ..registerLazySingleton(() => GetEditLog(sl()))
    ..registerLazySingleton(() => DeleteRows(sl()))
    ..registerLazySingleton(() => GetDeletedRows(sl()))
    ..registerLazySingleton(() => RestoreDeletedRows(sl()))
    ..registerLazySingleton(() => PurgeDeletedRows(sl()))
    ..registerLazySingleton(() => CheckIds(sl()))
    ..registerLazySingleton(() => RenumberIds(sl()));

  // ── presentation ──
  // App-wide (one workbook open at a time): singletons. Dialog-scoped: factories.
  sl
    ..registerLazySingleton(
      () => WorkbookCubit(
        open: sl(),
        summary: sl(),
        save: sl(),
        undo: sl(),
        recover: sl(),
        discard: sl(),
        settings: sl(),
        picker: sl(),
        changes: sl(),
      ),
    )
    ..registerLazySingleton(
      () => SheetCubit(
        analyze: sl(),
        listRows: sl(),
        changes: sl(),
        settings: sl(),
      ),
    )
    ..registerLazySingleton(
      () => RowEditorCubit(
        getRow: sl(),
        updateRow: sl(),
        setImage: sl(),
        parentImage: sl(),
        picker: sl(),
        changes: sl(),
      ),
    )
    ..registerLazySingleton(() => WikiCubit(fill: sl(), changes: sl()))
    ..registerFactory(
      () => AutofillCubit(proposals: sl(), apply: sl(), changes: sl()),
    )
    ..registerLazySingleton(
      () => IdCheckCubit(check: sl(), renumber: sl(), changes: sl()),
    )
    ..registerFactory(
      () => StructureCubit(
        addColumn: sl(),
        addRow: sl(),
        deleteRows: sl(),
        changes: sl(),
      ),
    )
    ..registerFactory(
      () => RecycleBinCubit(
        list: sl(),
        restore: sl(),
        purge: sl(),
        changes: sl(),
      ),
    )
    ..registerFactory(
      () => SettingsCubit(
        sl(),
        sl(),
        translationBridge: sl(instanceName: translationsEngine),
      ),
    );

  // ── translations ──
  sl
    ..registerLazySingleton<TranslationDataSource>(
      () => TranslationDataSource(sl(instanceName: translationsEngine), sl()),
    )
    ..registerLazySingleton<TranslationRepository>(
      () => translationRepository ?? TranslationRepositoryImpl(sl()),
    )
    ..registerLazySingleton(() => TranslationProjectStore(prefs!))
    ..registerLazySingleton(
      () => TranslationCubit(repository: sl(), store: sl(), prefs: prefs!),
    );

  // ── what the window-close prompt asks about ──
  sl<UnsavedWork>()
    ..register(
      UnsavedSource(
        id: 'workbook',
        label: () =>
            'Data: ${sl<WorkbookCubit>().state.summary?.fileName ?? 'workbook'}',
        isDirty: () => sl<WorkbookCubit>().state.summary?.dirty ?? false,
        save: () => sl<WorkbookCubit>().save(),
      ),
    )
    ..register(
      UnsavedSource(
        id: 'translations',
        label: () =>
            'Translations: ${sl<TranslationCubit>().state.summary?.sheet?.fileName ?? 'sheet'}',
        isDirty: () => sl<TranslationCubit>().state.dirty,
        save: () => sl<TranslationCubit>().save(),
      ),
    );
}
