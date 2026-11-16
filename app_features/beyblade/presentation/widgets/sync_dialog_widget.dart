import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_state.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/sync_progress_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SyncDialogLauncher {
  /// Opens the AppDialogWidget and automatically starts the sync
  /// if it isn't already running.
  static Future<void> showAndStartSync(BuildContext context) {
    // 1. Start the sync if it is currently idle
    final cubit = context.read<BeybladeSyncCubit>();
    if (cubit.state is! SyncRunning && cubit.state is! SyncFinished) {
      cubit.loadBundledMetadata();
    }

    // 2. Show your custom dialog
    return AppDialogWidget.show(
      context,
      title: 'Syncing Part Data',
      barrierDismissible:
          false, // Prevent the user from tapping away while it's loading
      content: BlocBuilder<BeybladeSyncCubit, BeybladeSyncState>(
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Please wait while we prepare the local parts database. This makes the app lighting fast!'),
              const SizedBox(height: 24),
              // Use our fixed view!
              SyncProgressView(state: state),
            ],
          );
        },
      ),
      actionButton: BlocBuilder<BeybladeSyncCubit, BeybladeSyncState>(
        builder: (context, state) {
          // If it's running, show a disabled button
          if (state is SyncRunning) {
            return const FilledButton(
              onPressed: null,
              child: Text('Please Wait...'),
            );
          }

          // If it failed, show a Retry button
          if (state is SyncError) {
            return FilledButton(
              onPressed: () =>
                  context.read<BeybladeSyncCubit>().loadBundledMetadata(),
              child: Text(TrTokens.retryTxt.tr),
            );
          }

          // If it finished, show a Close button
          return FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Optional: You could navigate them directly to the Search Page here!
            },
            child: const Text('Continue'),
          );
        },
      ),
    );
  }
}
