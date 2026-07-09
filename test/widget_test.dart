// Model parsing tests. (A full-app widget test would need Supabase.initialize,
// so we cover the JSON contract mapping here instead.)

import 'package:flutter_test/flutter_test.dart';

import 'package:gm_quick_chore_flutter_app/models/recording.dart';
import 'package:gm_quick_chore_flutter_app/models/chore.dart';

void main() {
  test('Recording.fromJson parses a done recording with chores', () {
    final rec = Recording.fromJson({
      'id': 'rec_1',
      'title': 'Errands',
      'status': 'done',
      'transcript': 'buy milk',
      'error': null,
      'chores': [
        {
          'id': 'c1',
          'content': 'Buy milk',
          'is_done': false,
          'position': 1,
          'due_date': null,
          'priority': null,
          'notes': null,
        },
      ],
      'created_at': '2026-07-09T12:00:00Z',
      'updated_at': '2026-07-09T12:00:18Z',
    });

    expect(rec.status, RecordingStatus.done);
    expect(rec.title, 'Errands');
    expect(rec.isTerminal, isTrue);
    expect(rec.chores.single.content, 'Buy milk');
    expect(rec.chores.single.dueDate, isNull); // v2
  });

  test('Recording maps failure codes to friendly messages', () {
    final rec = Recording.fromJson({
      'id': 'rec_2',
      'status': 'failed',
      'error': 'transcription_failed',
      'chores': <dynamic>[],
    });
    expect(rec.status, RecordingStatus.failed);
    expect(rec.friendlyError, contains("Couldn't understand"));
  });

  test('Chore.copyWith toggles is_done', () {
    const chore = Chore(id: 'c1', content: 'x', isDone: false);
    expect(chore.copyWith(isDone: true).isDone, isTrue);
  });
}
