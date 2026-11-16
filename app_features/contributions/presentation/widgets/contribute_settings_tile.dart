import 'package:clasher_st/features/contributions/contributions_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The Settings entry: put it in the settings list (e.g. under "About" / "Community").
class ContributeSettingsTile extends StatelessWidget {
  const ContributeSettingsTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.volunteer_activism_outlined),
        title: const Text('Help complete the catalog'),
        subtitle: const Text('See what\'s missing and send what you know - you\'re credited in the app'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(ContributionsRoutes.contribute),
      );
}
