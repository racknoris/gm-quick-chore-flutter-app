import 'package:flutter/material.dart';

import '../../models/chore.dart';

/// A single chore row: checkbox to toggle done, swipe/long-press affordance to
/// delete. Reorder + edit-text are v2.
class ChoreTile extends StatelessWidget {
  const ChoreTile({
    super.key,
    required this.chore,
    required this.onToggle,
    required this.onDelete,
  });

  final Chore chore;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(chore.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDelete(),
      child: CheckboxListTile(
        value: chore.isDone,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          chore.content,
          style: TextStyle(
            decoration: chore.isDone ? TextDecoration.lineThrough : null,
            color: chore.isDone ? Theme.of(context).disabledColor : null,
          ),
        ),
      ),
    );
  }
}
