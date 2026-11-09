import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/missing_data/presentation/cubits/row_editor/row_editor_cubit.dart';
import 'features/missing_data/presentation/cubits/sheet/sheet_cubit.dart';
import 'features/missing_data/presentation/cubits/wiki/wiki_cubit.dart';
import 'features/missing_data/presentation/cubits/workbook/workbook_cubit.dart';
import 'features/translations/presentation/cubits/translation_cubit.dart';

class MissingDataApp extends StatefulWidget {
  const MissingDataApp({super.key, this.router});

  final GoRouter? router;

  @override
  State<MissingDataApp> createState() => _MissingDataAppState();
}

class _MissingDataAppState extends State<MissingDataApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: sl<WorkbookCubit>()),
      BlocProvider.value(value: sl<SheetCubit>()),
      BlocProvider.value(value: sl<RowEditorCubit>()),
      BlocProvider.value(value: sl<WikiCubit>()),
      BlocProvider.value(value: sl<TranslationCubit>()),
    ],
    child: MaterialApp.router(
      title: 'Clasher Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
    ),
  );
}
