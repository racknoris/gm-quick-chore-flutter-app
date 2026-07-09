import 'package:equatable/equatable.dart';

/// A single chore or note extracted from a recording. Matches the chore object
/// in API.md. `dueDate`/`priority`/`notes` are v2 and always null in the MVP.
class Chore extends Equatable {
  const Chore({
    required this.id,
    required this.content,
    required this.isDone,
    this.position,
    this.dueDate,
    this.priority,
    this.notes,
  });

  final String id;
  final String content;
  final bool isDone;
  final num? position;
  final String? dueDate; // v2
  final String? priority; // v2
  final String? notes; // v2

  factory Chore.fromJson(Map<String, dynamic> json) {
    return Chore(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      isDone: json['is_done'] as bool? ?? false,
      position: json['position'] as num?,
      dueDate: json['due_date'] as String?,
      priority: json['priority'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Chore copyWith({String? content, bool? isDone}) {
    return Chore(
      id: id,
      content: content ?? this.content,
      isDone: isDone ?? this.isDone,
      position: position,
      dueDate: dueDate,
      priority: priority,
      notes: notes,
    );
  }

  @override
  List<Object?> get props => [id, content, isDone, position];
}
