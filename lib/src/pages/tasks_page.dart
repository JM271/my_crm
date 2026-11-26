import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import '../widgets/rows.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final startOfToday = dateOnly(now);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final open = store.openTasks;
    final overdue = open.where((t) => t.due.isBefore(startOfToday)).toList();
    final today = open
        .where(
          (t) => !t.due.isBefore(startOfToday) && t.due.isBefore(endOfToday),
        )
        .toList();
    final later = open.where((t) => !t.due.isBefore(endOfToday)).toList();
    final done = store.tasks.where((t) => t.done).toList()
      ..sort((a, b) => b.due.compareTo(a.due));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Tasks',
          subtitle: 'Small steps, great relationships.',
          action: PrimaryButton(
            label: 'New task',
            onPressed: () => showTaskForm(context),
          ),
        ),
        const SizedBox(height: 24),
        if (store.tasks.isEmpty)
          const Panel(
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              message: 'No tasks yet. Plan your first follow-up!',
            ),
          ),
        if (overdue.isNotEmpty)
          _TaskGroup(title: 'Overdue', tasks: overdue, accent: danger),
        if (today.isNotEmpty || store.tasks.isNotEmpty)
          _TaskGroup(
            title: 'Today',
            tasks: today,
            emptyMessage: 'Nothing left for today 🎉',
          ),
        if (later.isNotEmpty) _TaskGroup(title: 'Upcoming', tasks: later),
        if (done.isNotEmpty)
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  'Completed (${done.length})',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [for (final t in done) TaskTile(task: t)],
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    required this.title,
    required this.tasks,
    this.accent = ink,
    this.emptyMessage,
  });

  final String title;
  final List<Task> tasks;
  final Color accent;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(14, 18, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                '$title (${tasks.length})',
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (tasks.isEmpty && emptyMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Text(
                  emptyMessage!,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            for (final t in tasks) TaskTile(task: t),
          ],
        ),
      ),
    );
  }
}
