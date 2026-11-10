import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../di/service_locator.dart';
import '../services/unsaved_work.dart';

/// The Studio's frame: the sections on the left, the current one on the right. Owns the one prompt that asks
/// before the window closes (title-bar x, Alt+F4, Cmd+Q) while anything is unsaved, in any section.
class StudioShell extends StatefulWidget {
  const StudioShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const sections = <({IconData icon, IconData selected, String label})>[
    (
      icon: Icons.table_chart_outlined,
      selected: Icons.table_chart,
      label: 'Data',
    ),
    (
      icon: Icons.translate_outlined,
      selected: Icons.translate,
      label: 'Translations',
    ),
    (
      icon: Icons.rocket_launch_outlined,
      selected: Icons.rocket_launch,
      label: 'Publish',
    ),
    (
      icon: Icons.travel_explore_outlined,
      selected: Icons.travel_explore,
      label: 'Scrapers',
    ),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  late final AppLifecycleListener _exitGuard = AppLifecycleListener(
    onExitRequested: _onExitRequested,
  );

  @override
  void initState() {
    super.initState();
    _exitGuard; // start listening
  }

  @override
  void dispose() {
    _exitGuard.dispose();
    super.dispose();
  }

  /// Save / Don't save / Cancel, listing what's unsaved. Every edit is also in a recovery file, so even a hard
  /// kill loses nothing, but the normal way out should never be a silent discard.
  Future<AppExitResponse> _onExitRequested() async {
    final work = sl<UnsavedWork>();
    final dirty = work.dirty;
    if (dirty.isEmpty || !mounted) return AppExitResponse.exit;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Save before closing?'),
              const SizedBox(height: 8),
              for (final d in dirty) Text('•  ${d.label()}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text("Don't save"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      return await work.saveAll()
          ? AppExitResponse.exit
          : AppExitResponse.cancel;
    }
    return choice == 'discard' ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: widget.shell.currentIndex,
            labelType: NavigationRailLabelType.all,
            backgroundColor: cs.surfaceContainerLow,
            onDestinationSelected: (i) => widget.shell.goBranch(
              i,
              initialLocation: i == widget.shell.currentIndex,
            ),
            destinations: [
              for (final s in StudioShell.sections)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  selectedIcon: Icon(s.selected),
                  label: Text(s.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.shell),
        ],
      ),
    );
  }
}
