import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/missing_data/presentation/cubits/workbook/workbook_cubit.dart';
import '../../features/missing_data/presentation/pages/home_page.dart';
import '../../features/missing_data/presentation/pages/workbook_page.dart';
import '../../features/settings/presentation/cubit/settings_cubit.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/translations/presentation/pages/translations_page.dart';
import '../di/service_locator.dart';
import 'studio_shell.dart';

abstract final class Routes {
  static const home = '/';
  static const workbook = '/workbook';
  static const translations = '/translations';
  static const settings = '/settings';
}

/// One branch per section; each keeps its state while another is shown (an open workbook stays open while you
/// work on translations).
GoRouter buildRouter() => GoRouter(
  initialLocation: Routes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => StudioShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
            GoRoute(
              path: Routes.workbook,
              // Nothing open (e.g. a restored URL) -> back to the start page.
              redirect: (_, _) =>
                  sl<WorkbookCubit>().state.isOpen ? null : Routes.home,
              builder: (_, _) => const WorkbookPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.translations,
              builder: (_, _) => const TranslationsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => BlocProvider(
                create: (_) => sl<SettingsCubit>(),
                child: const SettingsPage(),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
