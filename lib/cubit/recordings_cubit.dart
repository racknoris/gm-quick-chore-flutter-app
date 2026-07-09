import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/recording.dart';
import '../models/chore.dart';
import '../services/api_client.dart';

enum ListPhase { loading, ready, error }

class RecordingsState {
  const RecordingsState({
    required this.phase,
    this.recordings = const [],
    this.error,
  });

  final ListPhase phase;
  final List<Recording> recordings;
  final String? error;
}

/// Owns the history list and chore mutations on it.
class RecordingsCubit extends Cubit<RecordingsState> {
  RecordingsCubit(this._api)
      : super(const RecordingsState(phase: ListPhase.loading));

  final ApiClient _api;

  Future<void> load() async {
    emit(const RecordingsState(phase: ListPhase.loading));
    try {
      final recs = await _api.listRecordings();
      emit(RecordingsState(phase: ListPhase.ready, recordings: recs));
    } catch (e) {
      emit(RecordingsState(phase: ListPhase.error, error: e.toString()));
    }
  }

  Future<void> toggleChore(String recordingId, Chore chore) async {
    // Optimistic update, revert on failure.
    _replaceChore(recordingId, chore.copyWith(isDone: !chore.isDone));
    try {
      await _api.updateChore(chore.id, isDone: !chore.isDone);
    } catch (_) {
      _replaceChore(recordingId, chore); // revert
    }
  }

  Future<void> deleteChore(String recordingId, Chore chore) async {
    _removeChore(recordingId, chore.id);
    try {
      await _api.deleteChore(chore.id);
    } catch (_) {
      await load(); // resync on failure
    }
  }

  Future<void> retry(String recordingId) async {
    try {
      await _api.retryRecording(recordingId);
      await load();
    } catch (e) {
      emit(RecordingsState(
        phase: ListPhase.error,
        recordings: state.recordings,
        error: e.toString(),
      ));
    }
  }

  void _replaceChore(String recordingId, Chore updated) {
    emit(RecordingsState(
      phase: ListPhase.ready,
      recordings: state.recordings.map((r) {
        if (r.id != recordingId) return r;
        return Recording(
          id: r.id,
          status: r.status,
          title: r.title,
          transcript: r.transcript,
          error: r.error,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
          chores: r.chores.map((c) => c.id == updated.id ? updated : c).toList(),
        );
      }).toList(),
    ));
  }

  void _removeChore(String recordingId, String choreId) {
    emit(RecordingsState(
      phase: ListPhase.ready,
      recordings: state.recordings.map((r) {
        if (r.id != recordingId) return r;
        return Recording(
          id: r.id,
          status: r.status,
          title: r.title,
          transcript: r.transcript,
          error: r.error,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
          chores: r.chores.where((c) => c.id != choreId).toList(),
        );
      }).toList(),
    ));
  }
}
