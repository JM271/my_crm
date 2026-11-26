import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import '../widgets/interaction_dialog.dart';
import '../widgets/rows.dart';
import 'contacts_page.dart';

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 6) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

List<StatData> overviewStats(CrmStore store) {
  final conversion = store.conversionRate;
  final won = store.countInStage(DealStage.gewonnen);
  return [
    StatData(
      title: 'Dealers',
      value: '${store.contacts.length}',
      subtitle: '+${store.contactsAddedThisMonth} this month',
      icon: Icons.storefront_outlined,
      color: forest,
      background: sage,
    ),
    StatData(
      title: 'Open deals',
      value: formatMoney(store.openPipelineValue),
      subtitle:
          'in ${store.openDeals.length} '
          '${store.openDeals.length == 1 ? 'deal' : 'deals'}',
      icon: Icons.trending_up_rounded,
      color: const Color(0xFFB36B35),
      background: const Color(0xFFF9EDE2),
    ),
    StatData(
      title: 'Won',
      value: formatMoney(store.wonValue),
      subtitle: '$won ${won == 1 ? 'deal' : 'deals'}',
      icon: Icons.emoji_events_outlined,
      color: const Color(0xFF5675B8),
      background: const Color(0xFFEBEFF9),
    ),
    StatData(
      title: 'Win rate',
      value: conversion == null ? '–' : formatPercent(conversion),
      subtitle: 'of closed deals',
      icon: Icons.show_chart_rounded,
      color: const Color(0xFF9A6EA8),
      background: const Color(0xFFF3EDF5),
    ),
  ];
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.isMobile,
    required this.contacts,
    required this.filter,
    required this.onPageSelect,
    required this.onAddContact,
  });

  final VoidCallback onAddContact;
  final bool isMobile;
  final List<Contact> contacts;
  final ContactFilter filter;
  final ValueChanged<int> onPageSelect;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final pipeline = PipelineCard(onOpen: () => onPageSelect(2));
        const activity = _ActivityCard();
        final tasks = _TodayTasksCard(onOpenTasks: () => onPageSelect(4));
        const followUp = _FollowUpCard();
        final contactsSection = _ContactsSection(
          contacts: contacts,
          filter: filter,
          onViewAll: () => onPageSelect(1),
          onAddContact: onAddContact,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: '${greetingFor(store.now())}, ${store.firstName} 👋',
              subtitle: "Here's what's happening at Molenstraat today.",
              action: isMobile
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showTaskForm(context),
                          icon: const Icon(Icons.add_task_rounded, size: 19),
                          label: const Text('New task'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: forest,
                            side: const BorderSide(color: forest),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        PrimaryButton(
                          label: 'New dealer',
                          onPressed: onAddContact,
                        ),
                      ],
                    ),
            ),
            if (isMobile) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'New task',
                  icon: Icons.add_task_rounded,
                  onPressed: () => showTaskForm(context),
                ),
              ),
            ],
            const SizedBox(height: 26),
            StatsGrid(stats: overviewStats(store)),
            const SizedBox(height: 26),
            if (wide) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: pipeline),
                    const SizedBox(width: 18),
                    const Expanded(flex: 4, child: activity),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: contactsSection),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [tasks, const SizedBox(height: 18), followUp],
                    ),
                  ),
                ],
              ),
            ] else ...[
              pipeline,
              const SizedBox(height: 18),
              tasks,
              const SizedBox(height: 18),
              followUp,
              const SizedBox(height: 18),
              activity,
              const SizedBox(height: 26),
              contactsSection,
            ],
          ],
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final items = store.activities.take(5).toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeading(
            title: 'Recent activity',
            subtitle: 'What happened lately',
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              message: 'No activity yet.',
            ),
          for (final a in items)
            _ActivityItem(
              name: store.contactById(a.contactId)?.name ?? 'Molenstraat',
              message: a.isInteraction
                  ? '${a.kind.label}: ${a.message}'
                  : a.message,
              time: formatAgo(a.at, now),
              onTap: a.contactId == null
                  ? null
                  : () => openContact(context, a.contactId!),
            ),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({
    required this.name,
    required this.message,
    required this.time,
    this.onTap,
  });

  final String name;
  final String message;
  final String time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ContactAvatar(name: name),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(time, style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _TodayTasksCard extends StatelessWidget {
  const _TodayTasksCard({required this.onOpenTasks});

  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final endOfToday = dateOnly(store.now()).add(const Duration(days: 1));
    final tasks = store.openTasks
        .where((t) => t.due.isBefore(endOfToday))
        .take(5)
        .toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Tasks for today',
            subtitle: tasks.isEmpty
                ? 'All caught up'
                : '${store.urgentTaskCount} open',
            trailing: IconButton(
              tooltip: 'Add task',
              onPressed: () => showTaskForm(context),
              icon: const Icon(Icons.add_rounded, color: forest),
            ),
          ),
          const SizedBox(height: 6),
          if (tasks.isEmpty)
            const EmptyState(
              icon: Icons.task_alt_rounded,
              message: 'No open tasks for today. Nice work!',
            ),
          for (final t in tasks) TaskTile(task: t),
          TextButton(
            onPressed: onOpenTasks,
            style: TextButton.styleFrom(foregroundColor: forest),
            child: const Text('All tasks'),
          ),
        ],
      ),
    );
  }
}

class _ContactsSection extends StatelessWidget {
  const _ContactsSection({
    required this.contacts,
    required this.filter,
    required this.onViewAll,
    required this.onAddContact,
  });

  final List<Contact> contacts;
  final ContactFilter filter;
  final VoidCallback onViewAll;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dealers',
                    style: TextStyle(
                      color: ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your newest dealers.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onViewAll,
              child: const Text(
                'View all',
                style: TextStyle(color: forest, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 3),
            IconButton(
              tooltip: 'Add dealer',
              onPressed: onAddContact,
              style: IconButton.styleFrom(
                backgroundColor: forest,
                foregroundColor: Colors.white,
                minimumSize: const Size(38, 38),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ContactList(
          contacts: contacts.take(5).toList(),
          totalCount: contacts.length,
          filter: filter,
        ),
      ],
    );
  }
}

/// Leads and customers nobody has called, visited or emailed for 30+ days.
class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard();

  static const days = 30;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final cutoff = now.subtract(const Duration(days: days));
    final due =
        <(Contact, DateTime?)>[
          for (final c in store.contacts)
            if (store.lastContactAt(c.id) case final last
                when last == null || last.isBefore(cutoff))
              (c, last),
        ]..sort((a, b) {
          // Partners and customers before leads, then the longest ago.
          final aLead = a.$1.status == ContactStatus.lead;
          final bLead = b.$1.status == ContactStatus.lead;
          if (aLead != bLead) return aLead ? 1 : -1;
          if (a.$2 == null || b.$2 == null) {
            return a.$2 == null ? (b.$2 == null ? 0 : -1) : 1;
          }
          return a.$2!.compareTo(b.$2!);
        });
    return Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Needs follow-up',
            subtitle: due.isEmpty
                ? 'Everyone heard from you recently'
                : '${due.length} ${due.length == 1 ? 'dealer' : 'dealers'} without contact in $days+ days',
          ),
          const SizedBox(height: 6),
          if (due.isEmpty)
            const EmptyState(
              icon: Icons.handshake_outlined,
              message: 'All leads and customers were contacted recently.',
            ),
          for (final (dealer, last) in due.take(5))
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openContact(context, dealer.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    ContactAvatar(name: dealer.name),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dealer.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastContactLabel(last, now),
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Log call',
                      onPressed: () =>
                          showLogInteraction(context, contactId: dealer.id),
                      icon: const Icon(
                        Icons.phone_in_talk_outlined,
                        size: 18,
                        color: forest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
