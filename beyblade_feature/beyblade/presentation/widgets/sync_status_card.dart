import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_state.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/sync_dialog_widget.dart';
import 'package:flutter/material.dart';

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key, required this.state});
  final BeybladeSyncState state;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(rc.horizontalPadding),
        child: _MetadataRow(state: state),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.state});
  final BeybladeSyncState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final s = state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.list_alt_outlined, color: cs.primary),
            SizedBox(width: rc.sm * 1.5),
            Text('Part Data', style: tt.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(_subtitle(s),
            style: tt.bodySmall?.copyWith(
                color: s is SyncError ? cs.error : cs.onSurfaceVariant)),

        SizedBox(height: rc.sm * 1.5),

        // Always show the button, but change its label and action based on state
        if (s is SyncRunning)
          FilledButton.icon(
            onPressed: () => SyncDialogLauncher.showAndStartSync(context),
            icon:
                const SizedBox(width: 16, height: 16, child: BeybladeSpinner()),
            label: const Text('View Progress'),
          )
        else if (s is SyncError)
          OutlinedButton.icon(
            onPressed: () => SyncDialogLauncher.showAndStartSync(context),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Sync'),
          )
        else
          FilledButton.icon(
            onPressed: () => SyncDialogLauncher.showAndStartSync(context),
            icon: const Icon(Icons.download),
            label: const Text('Force Update Data'),
          ),
      ],
    );
  }

  String _subtitle(BeybladeSyncState s) => switch (s) {
        SyncIdle() => 'Names, stats, and legality for every part.',
        SyncReady() => 'Loaded and ready.',
        SyncRunning() => 'Loading in the background…',
        SyncFinished(:final summary) => 'Loaded ${summary.totalRecords} parts.',
        SyncError(:final message) => message,
      };
}
