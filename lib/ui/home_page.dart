import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/auth_cubit.dart';
import '../cubit/record_cubit.dart';
import '../cubit/recordings_cubit.dart';
import '../models/recording.dart';
import 'recording_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    context.read<RecordingsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Chores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthCubit>().signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<RecordingsCubit>().load(),
        child: BlocBuilder<RecordingsCubit, RecordingsState>(
          builder: (context, state) {
            if (state.phase == ListPhase.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.phase == ListPhase.error) {
              return _CenteredMessage(
                icon: Icons.error_outline,
                text: state.error ?? 'Failed to load.',
              );
            }
            if (state.recordings.isEmpty) {
              return const _CenteredMessage(
                icon: Icons.mic_none,
                text: 'No recordings yet.\nTap the mic to capture your chores.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: state.recordings.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _RecordingTile(recording: state.recordings[i]),
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: const _RecordButton(),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (recording.status) {
      RecordingStatus.done =>
        '${recording.chores.length} chore(s)',
      RecordingStatus.failed => recording.friendlyError,
      _ => 'Processing…',
    };
    return ListTile(
      leading: _statusIcon(recording.status),
      title: Text(recording.title ?? 'Untitled'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecordingDetailPage(recordingId: recording.id),
        ));
      },
    );
  }

  Widget _statusIcon(RecordingStatus status) {
    return switch (status) {
      RecordingStatus.done => const Icon(Icons.check_circle, color: Colors.green),
      RecordingStatus.failed => const Icon(Icons.error, color: Colors.red),
      _ => const SizedBox(
          width: 24,
          height: 24,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
    };
  }
}

/// The record button reflects the full record -> upload -> poll flow.
class _RecordButton extends StatelessWidget {
  const _RecordButton();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RecordCubit, RecordState>(
      listener: (context, state) {
        if (state.phase == RecordPhase.done) {
          context.read<RecordingsCubit>().load();
          context.read<RecordCubit>().reset();
          if (state.recording != null) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RecordingDetailPage(
                recordingId: state.recording!.id,
              ),
            ));
          }
        } else if (state.phase == RecordPhase.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message ?? 'Something went wrong.')),
          );
          context.read<RecordCubit>().reset();
        }
      },
      builder: (context, state) {
        final cubit = context.read<RecordCubit>();
        final isRecording = state.phase == RecordPhase.recording;
        final isBusy = state.phase == RecordPhase.uploading ||
            state.phase == RecordPhase.creating ||
            state.phase == RecordPhase.processing;

        if (isBusy) {
          return FloatingActionButton.extended(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: Text(state.message ?? 'Working…'),
          );
        }

        return FloatingActionButton.extended(
          backgroundColor: isRecording ? Colors.red : null,
          onPressed: () =>
              isRecording ? cubit.stopAndProcess() : cubit.startRecording(),
          icon: Icon(isRecording ? Icons.stop : Icons.mic),
          label: Text(isRecording ? 'Stop' : 'Record'),
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Wrapped in a scrollable so RefreshIndicator works even when empty.
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(icon, size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    );
  }
}
