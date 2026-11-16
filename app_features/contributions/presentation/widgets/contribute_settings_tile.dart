import 'package:clasher_st/features/contributions/contributions_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The Settings entry: put it in the settings list (e.g. under "About" / "Community").
class ContributeSettingsTile extends StatelessWidget {
  const ContributeSettingsTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.add_photo_alternate_outlined),
        title: const Text('Send pictures'),
        subtitle: const Text('Help complete the catalog - you\'re credited in the app'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(ContributionsRoutes.contribute),
      );
}
