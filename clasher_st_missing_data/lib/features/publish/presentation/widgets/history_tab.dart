import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../cubits/history_cubit.dart';

/// Releases on the data repo and the translations repo, with their files.
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pub = sl<AppSettings>().publishing;
    return BlocBuilder<HistoryCubit, HistoryState>(
      builder: (context, s) => ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: Text('Releases', style: Theme.of(context).textTheme.titleMedium)),
          if (s.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          TextButton.icon(onPressed: context.read<HistoryCubit>().load, icon: const Icon(Icons.refresh), label: const Text('Reload')),
        ]),
        if (s.error != null) Text(s.error!, style: TextStyle(color: cs.error)),
        _RepoReleases(title: 'Data: ${pub.dataRepoSlug}', slug: pub.dataRepoSlug, releases: s.data, assets: s.assets),
        _RepoReleases(title: 'Translations: ${pub.translationsRepoSlug}', slug: pub.translationsRepoSlug, releases: s.translations, assets: s.assets),
      ]),
    );
  }
}

class _RepoReleases extends StatelessWidget {
  const _RepoReleases({required this.title, required this.slug, required this.releases, required this.assets});
  final String title;
  final String slug;
  final List<ReleaseInfo> releases;
  final Map<String, List<ReleaseAsset>> assets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      if (releases.isEmpty) Text('No releases (or gh can\'t read them).', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final r in releases)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ExpansionTile(
            onExpansionChanged: (open) {
              if (open) context.read<HistoryCubit>().loadAssets(slug, r.tag);
            },
            title: Text('${r.tag}${r.isLatest ? '   (latest)' : ''}${r.isDraft ? '   draft' : ''}'),
            subtitle: Text([if (r.name.isNotEmpty && r.name != r.tag) r.name, if (r.publishedAt != null) r.publishedAt!.toLocal().toString().substring(0, 16)].join(' · ')),
            children: [
              for (final a in assets['$slug@${r.tag}'] ?? const <ReleaseAsset>[])
                ListTile(
                  dense: true,
                  title: Text(a.name),
                  trailing: Text('${(a.size / 1024 / 1024).toStringAsFixed(2)} MB · ${a.downloads} downloads'),
                ),
            ],
          ),
        ),
    ]);
  }
}
