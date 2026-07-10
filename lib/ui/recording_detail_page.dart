import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/recordings_cubit.dart';
import '../models/recording.dart';
import 'widgets/chore_tile.dart';

/// Shows one recording's chores + transcript. Reads from the RecordingsCubit so
/// chore toggles/deletes stay in sync with the history list.
class RecordingDetailPage extends StatelessWidget {
  const RecordingDetailPage({super.key, required this.recordingId});

  final String recordingId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecordingsCubit, RecordingsState>(
      builder: (context, state) {
        final recording = state.recordings
            .where((r) => r.id == recordingId)
            .cast<Recording?>()
            .firstWhere((r) => r != null, orElse: () => null);

        if (recording == null) {
          return const Scaffold(
            body: Center(child: Text('Recording not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(recording.title ?? 'Recording'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete recording',
                onPressed: () => _confirmDelete(context, recording.id),
              ),
            ],
          ),
          body: _body(context, recording),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, String recordingId) async {
    final cubit = context.read<RecordingsCubit>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recording?'),
        content: const Text('This removes the recording and all its chores.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      cubit.deleteRecording(recordingId);
      navigator.pop(); // leave the detail page
    }
  }

  Widget _body(BuildContext context, Recording recording) {
    if (recording.status == RecordingStatus.failed) {
      return _FailedView(recording: recording);
    }
    if (recording.status != RecordingStatus.done) {
      return const Center(child: CircularProgressIndicator());
    }

    final cubit = context.read<RecordingsCubit>();
    return ListView(
      children: [
        if (recording.chores.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No chores found in this recording.'),
          )
        else
          ...recording.chores.map(
            (chore) => ChoreTile(
              chore: chore,
              onToggle: () => cubit.toggleChore(recording.id, chore),
              onDelete: () => cubit.deleteChore(recording.id, chore),
            ),
          ),
        if (recording.transcript != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transcript',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(recording.transcript!),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(recording.friendlyError),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: () => context.read<RecordingsCubit>().retry(recording.id),
          ),
        ],
      ),
    );
  }
}
