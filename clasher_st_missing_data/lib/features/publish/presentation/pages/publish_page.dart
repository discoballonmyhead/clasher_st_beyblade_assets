import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../cubits/data_release_cubit.dart';
import '../cubits/history_cubit.dart';
import '../cubits/packaging_cubit.dart';
import '../cubits/translations_release_cubit.dart';
import '../widgets/data_release_tab.dart';
import '../widgets/history_tab.dart';
import '../widgets/packaging_tab.dart';
import '../widgets/translations_release_tab.dart';

/// Everything that leaves the Studio: the data release (data repo), the language packs (translations repo), what
/// the packager writes (packaging profiles) and the releases so far.
class PublishPage extends StatelessWidget {
  const PublishPage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: sl<DataReleaseCubit>()..load()),
      BlocProvider.value(value: sl<TranslationsReleaseCubit>()..load()),
      BlocProvider.value(value: sl<PackagingCubit>()..load()),
      BlocProvider.value(value: sl<HistoryCubit>()), // loads when its tab opens
    ],
    child: DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Publish'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Data release'),
              Tab(text: 'Translations release'),
              Tab(text: 'Packaging'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(children: [DataReleaseTab(), TranslationsReleaseTab(), PackagingTab(), HistoryTab()]),
      ),
    ),
  );
}
