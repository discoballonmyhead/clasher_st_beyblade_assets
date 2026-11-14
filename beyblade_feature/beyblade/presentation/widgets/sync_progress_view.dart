import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_state.dart';
import 'package:flutter/material.dart';

class SyncProgressView extends StatelessWidget {
  const SyncProgressView({super.key, required this.state});

  final BeybladeSyncState state; // Changed from SyncRunning!

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;

    // Correctly extract the fraction and message based on the Cubit's state
    final (double fraction, String message) = switch (state) {
      SyncIdle() => (0.0, 'Waiting to start…'),
      SyncReady() => (1.0, 'Already up to date.'),
      SyncRunning(:final progress) => switch (progress) {
          SyncStarted() => (0.0, 'Starting…'),
          SyncInProgress(:final fraction, :final message) => (
              fraction,
              message
            ),
          _ => (0.0, 'Processing…')
        },
      SyncFinished(:final summary) => (
          1.0,
          'Loaded ${summary.totalRecords} parts successfully.'
        ),
      SyncError(:final message) => (0.0, message),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(rc.borderRadius / 2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            // Turn the bar red if it fails, green if it finishes
            color: state is SyncError
                ? cs.error
                : (state is SyncFinished ? Colors.green : cs.primary),
          ),
        ),
        SizedBox(height: rc.sm),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: state is SyncError ? cs.error : cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
