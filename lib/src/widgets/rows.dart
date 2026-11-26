import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../pages/contact_detail_page.dart';
import '../theme.dart';
import 'common.dart';
import 'consignment_forms.dart';
import 'forms.dart';
import 'interaction_dialog.dart';

void openContact(BuildContext context, String contactId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ContactDetailPage(contactId: contactId),
    ),
  );
}

Future<void> deleteContactWithConfirm(
  BuildContext context,
  Contact contact,
) async {
  final store = CrmScope.read(context);
  final held = store.bikesAt(contact.id).length;
  if (held > 0) {
    showMessage(
      context,
      '${contact.name} still has $held consignment '
      '${held == 1 ? 'bike' : 'bikes'}. Mark them as returned, sold or move '
      'them first.',
    );
    return;
  }
  final ok = await confirmDelete(
    context,
    title: contact.isPrivate ? 'Delete private customer?' : 'Delete dealer?',
    message: contact.isPrivate
        ? '${contact.name} will be deleted, along with their deals, tasks '
              'and activity. This cannot be undone.'
        : '${contact.name} will be deleted, along with its deals, tasks, '
              'activity and consignment history. This cannot be undone.',
  );
  if (!ok) return;
  store.deleteContact(contact.id);
  if (context.mounted) showMessage(context, '${contact.name} was deleted.');
}

class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.contact, required this.compact});

  final Contact contact;
  final bool compact;

  /// Below this width (phones) the name gets the whole row and the details
  /// move underneath it instead of into their own columns.
  static const narrowWidth = 600.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _build(context, narrow: constraints.maxWidth < narrowWidth),
  );

  Widget _build(BuildContext context, {required bool narrow}) {
    final store = CrmScope.of(context);
    final now = store.now();
    final lastContact = switch (store.lastContactAt(contact.id)) {
      null => 'No contact',
      final last => formatDay(last, now),
    };
    final reach = [
      contact.phone,
      contact.email,
      contact.websiteLabel,
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final columns = !compact && !narrow;
    // Phone layout: how to reach them, and when they were last contacted.
    final phoneLine = [
      if (reach.isNotEmpty) reach,
      if (lastContact != 'No contact') 'Last contact $lastContact',
    ].join(' · ');
    return InkWell(
      onTap: () => openContact(context, contact.id),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          compact ? 10 : 13,
          6,
          compact ? 10 : 13,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            ContactAvatar(name: contact.name, radius: compact ? 18 : 21),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The full name, wrapping onto more lines if needed.
                  Text(
                    contact.name,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    contact.summary.isNotEmpty
                        ? contact.summary
                        : (contact.contactPerson.isNotEmpty
                              ? contact.contactPerson
                              : 'No details yet'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  if (narrow && !compact && phoneLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      phoneLine,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (columns) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(
                  reach,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
            const SizedBox(width: 8),
            StatusTag(status: contact.status),
            if (columns) ...[
              const SizedBox(width: 15),
              Tooltip(
                message: 'Last contact',
                child: SizedBox(
                  width: 70,
                  child: Text(
                    lastContact,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ),
            ],
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: muted,
              ),
              onSelected: (action) {
                switch (action) {
                  case 'open':
                    openContact(context, contact.id);
                  case 'edit':
                    showContactForm(context, existing: contact);
                  case 'log':
                    showLogInteraction(context, contactId: contact.id);
                  case 'deal':
                    showDealForm(context, contactId: contact.id);
                  case 'bikes':
                    showBikeForm(context, contactId: contact.id);
                  case 'task':
                    showTaskForm(context, contactId: contact.id);
                  case 'delete':
                    deleteContactWithConfirm(context, contact);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'open', child: Text('Open')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'log',
                  child: Text('Log call / visit / note'),
                ),
                const PopupMenuItem(value: 'deal', child: Text('Add deal')),
                // Consignment is only for shops.
                if (!contact.isPrivate)
                  const PopupMenuItem(
                    value: 'bikes',
                    child: Text('Place bikes on consignment'),
                  ),
                const PopupMenuItem(value: 'task', child: Text('Add task')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DealTile extends StatelessWidget {
  const DealTile({
    super.key,
    required this.deal,
    this.showContact = true,
    this.showStage = true,
  });

  final Deal deal;
  final bool showContact;

  /// Off inside a stage column, where the stage is already obvious.
  final bool showStage;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final contact = store.contactById(deal.contactId);
    final subtitle = [
      if (showContact && contact != null) contact.name,
      if (deal.units > 0) '${deal.units} ${deal.units == 1 ? 'unit' : 'units'}',
      if (showStage) deal.stage.label,
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showContactOrEdit(context, contact),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.circle, size: 9, color: stageColor(deal.stage)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deal.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(deal.value),
              style: TextStyle(
                color: deal.stage == DealStage.verloren ? muted : ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: deal.stage == DealStage.verloren
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            DealMenu(deal: deal),
          ],
        ),
      ),
    );
  }

  void showContactOrEdit(BuildContext context, Contact? contact) {
    if (showContact && contact != null) {
      openContact(context, contact.id);
    } else {
      showDealForm(context, existing: deal);
    }
  }
}

class DealMenu extends StatelessWidget {
  const DealMenu({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Deal actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 20, color: muted),
      onSelected: (action) async {
        final store = CrmScope.read(context);
        if (action.startsWith('stage:')) {
          final stage = DealStage.values.byName(action.substring(6));
          store.moveDeal(deal.id, stage);
          if (stage == DealStage.gewonnen) {
            showMessage(context, 'Congratulations! "${deal.title}" is won 🎉');
          }
          return;
        }
        if (action == 'edit') {
          showDealForm(context, existing: deal);
        } else if (action == 'delete') {
          final ok = await confirmDelete(
            context,
            title: 'Delete deal?',
            message: '"${deal.title}" will be permanently deleted.',
          );
          if (ok) store.deleteDeal(deal.id);
        }
      },
      itemBuilder: (_) => [
        for (final stage in DealStage.values)
          if (stage != deal.stage)
            PopupMenuItem(
              value: 'stage:${stage.name}',
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: stageColor(stage)),
                  const SizedBox(width: 10),
                  Text('Move to ${stage.label.toLowerCase()}'),
                ],
              ),
            ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: danger)),
        ),
      ],
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.showContact = true});

  final Task task;
  final bool showContact;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final contact = showContact ? store.contactById(task.contactId) : null;
    final overdue = !task.done && task.due.isBefore(now);
    return Row(
      children: [
        Checkbox(
          value: task.done,
          activeColor: forest,
          onChanged: (value) => store.toggleTask(task.id, value ?? false),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showTaskForm(context, existing: task),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: task.done ? muted : ink,
                      fontSize: 13,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatDayTime(task.due, now),
                          style: TextStyle(
                            color: overdue ? danger : muted,
                            fontWeight: overdue ? FontWeight.w700 : null,
                          ),
                        ),
                        if (contact != null)
                          TextSpan(text: ' · ${contact.name}'),
                      ],
                    ),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Task actions',
          icon: const Icon(Icons.more_horiz_rounded, size: 20, color: muted),
          onSelected: (action) {
            switch (action) {
              case 'edit':
                showTaskForm(context, existing: task);
              case 'contact':
                openContact(context, task.contactId!);
              case 'delete':
                store.deleteTask(task.id);
                showMessage(context, 'Task deleted.');
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (contact != null)
              const PopupMenuItem(value: 'contact', child: Text('Open dealer')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: danger)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Stacked pipeline bar + legend, computed from the deals in the store.
class PipelineCard extends StatelessWidget {
  const PipelineCard({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final counts = {
      for (final s in DealStage.pipeline) s: store.countInStage(s),
    };
    final total = counts.values.fold(0, (a, b) => a + b);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Sales pipeline',
            subtitle: 'Your deals at a glance',
            trailing: onOpen == null
                ? null
                : IconButton(
                    tooltip: 'Go to deals',
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward_rounded, color: muted),
                  ),
          ),
          const SizedBox(height: 22),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                formatMoney(store.openPipelineValue),
                style: const TextStyle(
                  fontSize: 27,
                  letterSpacing: -0.6,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'open in ${store.openDeals.length} '
                  '${store.openDeals.length == 1 ? 'deal' : 'deals'}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 9,
              child: total == 0
                  ? const ColoredBox(color: line)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in DealStage.pipeline)
                          if (counts[s]! > 0)
                            Expanded(
                              flex: counts[s]!,
                              child: ColoredBox(color: stageColor(s)),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              for (final s in DealStage.pipeline)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 9, color: stageColor(s)),
                    const SizedBox(width: 7),
                    Text(
                      s.label,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${counts[s]}',
                      style: const TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
