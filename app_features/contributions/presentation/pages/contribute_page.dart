import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/contribute_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Settings -> Send pictures. Built with plain Material widgets so it works in any theme; swap in the app's
/// own components (Holo cards, TrTokens texts) as you like.
class ContributePage extends StatelessWidget {
  const ContributePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ContributeCubit, ContributeState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.error!))),
      builder: (context, s) => Scaffold(
        appBar: AppBar(title: const Text('Send pictures')),
        body: SafeArea(
          child: s.loading
              ? const Center(child: CircularProgressIndicator())
              : s.receipt != null
                  ? const _Thanks()
                  : _Form(s: s),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.s});
  final ContributeState s;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ContributeCubit>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (!s.configured) {
      return const _Notice(
        icon: Icons.cloud_off_outlined,
        text: 'Sending pictures isn\'t set up in this version of the app.',
      );
    }
    if (s.contributor == null) {
      return const _Notice(
        icon: Icons.person_outline,
        text: 'Sign in to send pictures. We show your username, or the credit you choose, next to the '
            'pictures we use.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Help complete the catalog with pictures of parts, boxes and bladers. Every picture is checked '
          'before it appears in the app, and you\'re credited on the part\'s page.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text('Sending as ${s.contributor!.username}', style: tt.labelMedium),
        const SizedBox(height: 16),

        // 1. what it's of
        Text('1. What is it a picture of?', style: tt.titleSmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<TargetGroup>(
            key: const ValueKey('contribute-group'),
            segments: [
              for (final g in TargetGroup.values) ButtonSegment(value: g, label: Text(g.label)),
            ],
            selected: {s.group},
            onSelectionChanged: (v) => cubit.setGroup(v.first),
          ),
        ),
        const SizedBox(height: 8),
        if (!s.isOther) ...[
          if (s.target != null)
            InputChip(
              key: const ValueKey('contribute-target'),
              avatar: const Icon(Icons.check_circle, size: 18),
              label: Text(s.target!.name),
              onDeleted: () => cubit.selectTarget(null),
            )
          else ...[
            TextField(
              key: const ValueKey('contribute-search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.group == TargetGroup.parts ? 'Search parts by name or code' : 'Search',
                suffixIcon: s.searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              onChanged: cubit.search,
            ),
            for (final t in s.results)
              ListTile(
                dense: true,
                title: Text(t.name),
                subtitle: Text('${t.type} #${t.id}'),
                onTap: () => cubit.selectTarget(t),
              ),
            if (s.results.isEmpty && s.query.isNotEmpty && !s.searching)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing found. Not in the catalog yet? Choose Other and describe it.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ],
          if (s.target?.isBlader == true) ...[
            const SizedBox(height: 8),
            SegmentedButton<ContributionKind>(
              key: const ValueKey('contribute-kind'),
              segments: const [
                ButtonSegment(value: ContributionKind.image, label: Text('Portrait')),
                ButtonSegment(value: ContributionKind.fullBodyImage, label: Text('Full body')),
              ],
              selected: {s.kind},
              onSelectionChanged: (v) => cubit.setKind(v.first),
            ),
          ],
        ],
        const SizedBox(height: 16),

        // 2. the picture
        Text('2. The picture', style: tt.titleSmall),
        const SizedBox(height: 8),
        if (s.picture != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(s.picture!.bytes,
                    height: 220, width: double.infinity, fit: BoxFit.contain, gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 220, child: Icon(Icons.broken_image))),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filledTonal(
                  tooltip: 'Remove',
                  onPressed: cubit.clearPicture,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('contribute-gallery'),
              onPressed: () => cubit.pickPicture(),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.picture == null ? 'Choose a picture' : 'Choose another'),
            ),
            OutlinedButton.icon(
              onPressed: () => cubit.pickPicture(camera: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. credit + note
        Text('3. Credit and note', style: tt.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('contribute-credit'),
          initialValue: s.credit,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Credit (optional)',
            helperText: 'How you\'re credited in the app, e.g. your name or @handle. '
                'Empty: ${s.contributor!.username}.',
            helperMaxLines: 2,
          ),
          onChanged: cubit.setCredit,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('contribute-note'),
          initialValue: s.note,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: s.isOther ? 'What is it?' : 'Note (optional)',
            helperText: s.isOther ? 'Required: name the part, box or blader.' : 'Anything we should know.',
          ),
          onChanged: cubit.setNote,
        ),
        CheckboxListTile(
          key: const ValueKey('contribute-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.consent,
          onChanged: (v) => cubit.setConsent(v ?? false),
          title: const Text('I took this picture or may share it, and it can be shown in the app.'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('contribute-send'),
          onPressed: s.canSubmit ? cubit.send : null,
          icon: s.submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(s.submitting ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}

class _Thanks extends StatelessWidget {
  const _Thanks();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Thanks!', style: tt.headlineSmall),
            const SizedBox(height: 6),
            const Text('We\'ll check your picture and add it with your credit.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('contribute-another'),
              onPressed: context.read<ContributeCubit>().another,
              child: const Text('Send another'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
