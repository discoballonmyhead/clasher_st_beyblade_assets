import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/missing_data/presentation/cubits/workbook/workbook_cubit.dart';
import '../../features/missing_data/presentation/pages/home_page.dart';
import '../../features/missing_data/presentation/pages/workbook_page.dart';
import '../../features/settings/presentation/cubit/settings_cubit.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../di/service_locator.dart';

abstract final class Routes {
  static const home = '/';
  static const workbook = '/workbook';
  static const settings = '/settings';
}

GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
        GoRoute(
          path: Routes.workbook,
          // Nothing open (e.g. a restored URL) -> back to the start page.
          redirect: (_, _) => sl<WorkbookCubit>().state.isOpen ? null : Routes.home,
          builder: (_, _) => const WorkbookPage(),
        ),
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => BlocProvider(create: (_) => sl<SettingsCubit>(), child: const SettingsPage()),
        ),
      ],
    );
