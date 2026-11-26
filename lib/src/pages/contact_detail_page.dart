import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/consignment_forms.dart';
import '../widgets/forms.dart';
import '../widgets/interaction_dialog.dart';
import '../widgets/rows.dart';

class ContactDetailPage extends StatelessWidget {
  const ContactDetailPage({super.key, required this.contactId});

  final String contactId;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final contact = store.contactById(contactId);
    if (contact == null) {
      // Deleted while open.
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.white),
        body: const EmptyState(
          icon: Icons.person_off_outlined,
          message: 'This contact no longer exists.',
        ),
      );
    }
    final private = contact.isPrivate;
    final deals = store.dealsFor(contact.id);
    final tasks = store.tasksFor(contact.id);
    final activity = store.activitiesFor(contact.id);
    final now = store.now();
    final openValue = deals
        .where((d) => d.stage.isOpen)
        .fold<double>(0, (sum, d) => sum + d.value);

    final info = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ContactAvatar(name: contact.name, radius: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      private
                          ? 'Private customer'
                          : contact.type == ShopType.unknown
                          ? 'Dealer · type not set'
                          : contact.type.label,
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ContactStatus.optionsFor(contact.kind))
                ChoiceChip(
                  label: Text(s.label),
                  selected: contact.status == s,
                  selectedColor: statusColors(s).$1,
                  labelStyle: TextStyle(
                    color: contact.status == s ? statusColors(s).$2 : muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  side: const BorderSide(color: line),
                  showCheckmark: false,
                  onSelected: (_) =>
                      store.updateContact(contact.copyWith(status: s)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: line),
          if (!private)
            _InfoLine(
              icon: Icons.person_outline_rounded,
              value: contact.contactPerson.isEmpty
                  ? 'No contact person'
                  : contact.contactPerson,
              empty: contact.contactPerson.isEmpty,
            ),
          _InfoLine(
            icon: Icons.place_outlined,
            value: contact.fullAddress.isEmpty
                ? 'No address'
                : contact.fullAddress,
            empty: contact.fullAddress.isEmpty,
            link: contact.mapUri,
          ),
          _InfoLine(
            icon: Icons.phone_outlined,
            value: contact.phone.isEmpty ? 'No phone number' : contact.phone,
            empty: contact.phone.isEmpty,
            link: contact.phone.isEmpty
                ? null
                : Uri(
                    scheme: 'tel',
                    path: contact.phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                  ),
          ),
          _InfoLine(
            icon: Icons.mail_outline_rounded,
            value: contact.email.isEmpty ? 'No email address' : contact.email,
            empty: contact.email.isEmpty,
            link: contact.email.isEmpty
                ? null
                : Uri(scheme: 'mailto', path: contact.email),
          ),
          if (!private)
            _InfoLine(
              icon: Icons.language_rounded,
              value: contact.website.isEmpty
                  ? 'No website'
                  : contact.websiteLabel,
              empty: contact.website.isEmpty,
              link: contact.websiteUri,
            ),
          _InfoLine(
            icon: Icons.calendar_today_outlined,
            value: 'Added: ${formatDay(contact.createdAt, now)}',
          ),
          _InfoLine(
            icon: Icons.trending_up_rounded,
            value: 'Open value: ${formatMoney(openValue)}',
          ),
          const SizedBox(height: 10),
          _NotesEditor(contact: contact),
        ],
      ),
    );

    final dealsPanel = Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Deals',
            subtitle: '${deals.length} ${deals.length == 1 ? 'deal' : 'deals'}',
            trailing: IconButton(
              tooltip: 'Add deal',
              onPressed: () => showDealForm(context, contactId: contact.id),
              icon: const Icon(Icons.add_rounded, color: forest),
            ),
          ),
          const SizedBox(height: 6),
          if (deals.isEmpty)
            EmptyState(
              icon: Icons.trending_up_rounded,
              message: private
                  ? 'No deals with this customer yet.'
                  : 'No deals with this dealer yet.',
            ),
          for (final d in deals) DealTile(deal: d, showContact: false),
        ],
      ),
    );

    final held = store.bikesAt(contact.id);
    final pastBikes = store
        .bikesFor(contact.id)
        .where((b) => !b.isAtDealer)
        .toList();
    final bikesPanel = Panel(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 12),
            child: PanelHeading(
              title: 'Consignment',
              subtitle: held.isEmpty
                  ? 'No bikes in depot here'
                  : '${held.length} ${held.length == 1 ? 'bike' : 'bikes'} '
                        'in depot · '
                        '${formatMoney(held.fold<double>(0, (s, b) => s + b.price))}',
              trailing: IconButton(
                tooltip: 'Place bikes',
                onPressed: () => showBikeForm(context, contactId: contact.id),
                icon: const Icon(Icons.add_rounded, color: forest),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (held.isEmpty && pastBikes.isEmpty)
            const EmptyState(
              icon: Icons.pedal_bike_rounded,
              message: 'No consignment bikes at this dealer.',
            ),
          for (final b in held) BikeRow(bike: b, showDealer: false),
          if (pastBikes.isNotEmpty)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 22),
                title: Text(
                  'Sold & returned (${pastBikes.length})',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  for (final b in pastBikes)
                    BikeRow(bike: b, showDealer: false),
                ],
              ),
            ),
        ],
      ),
    );

    final tasksPanel = Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Tasks',
            subtitle: '${tasks.where((t) => !t.done).length} open',
            trailing: IconButton(
              tooltip: 'Add task',
              onPressed: () => showTaskForm(context, contactId: contact.id),
              icon: const Icon(Icons.add_rounded, color: forest),
            ),
          ),
          const SizedBox(height: 6),
          if (tasks.isEmpty)
            EmptyState(
              icon: Icons.task_alt_rounded,
              message: private
                  ? 'No tasks for this customer.'
                  : 'No tasks for this dealer.',
            ),
          for (final t in tasks) TaskTile(task: t, showContact: false),
        ],
      ),
    );

    final activityPanel = Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Timeline',
            subtitle: lastContactLabel(store.lastContactAt(contact.id), now),
            trailing: FilledButton.tonalIcon(
              onPressed: () =>
                  showLogInteraction(context, contactId: contact.id),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Log'),
              style: FilledButton.styleFrom(
                backgroundColor: sage,
                foregroundColor: forest,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (activity.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              message:
                  'Nothing has happened yet. Log your first call or visit.',
            ),
          for (final a in activity)
            _TimelineEntry(activity: a, dealer: contact),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          private ? 'Private customer' : 'Dealer',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        shape: const Border(bottom: BorderSide(color: line)),
        actions: [
          if (contact.email.isNotEmpty)
            IconButton(
              tooltip: 'Copy email',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copy(context, contact.email),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showContactForm(context, existing: contact),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, color: danger),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await deleteContactWithConfirm(context, contact);
              if (store.contactById(contact.id) == null) navigator.pop();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final pad = constraints.maxWidth < 680 ? 18.0 : 36.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 24, pad, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: info),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                dealsPanel,
                                const SizedBox(height: 18),
                                if (!private) ...[
                                  bikesPanel,
                                  const SizedBox(height: 18),
                                ],
                                tasksPanel,
                                const SizedBox(height: 18),
                                activityPanel,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          info,
                          const SizedBox(height: 18),
                          dealsPanel,
                          const SizedBox(height: 18),
                          if (!private) ...[
                            bikesPanel,
                            const SizedBox(height: 18),
                          ],
                          tasksPanel,
                          const SizedBox(height: 18),
                          activityPanel,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    showMessage(context, 'Copied: $text');
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.value,
    this.empty = false,
    this.link,
  });

  final IconData icon;
  final String value;
  final bool empty;

  /// Opened on tap (tel:, mailto:, https:).
  final Uri? link;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: empty ? muted : (link != null ? forest : ink),
        fontSize: 13,
        fontWeight: link != null ? FontWeight.w600 : null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: link == null
            ? null
            : () async {
                final ok = await launchUrl(link!);
                if (!ok && context.mounted) {
                  showMessage(context, 'Could not open $value');
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 17, color: muted),
              const SizedBox(width: 12),
              Expanded(child: text),
              if (link != null)
                const Icon(Icons.north_east_rounded, size: 14, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesEditor extends StatefulWidget {
  const _NotesEditor({required this.contact});

  final Contact contact;

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final _controller = TextEditingController(text: widget.contact.notes);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_NotesEditor old) {
    super.didUpdateWidget(old);
    // Pick up edits made elsewhere (e.g. the edit dialog) when not typing.
    if (!_focus.hasFocus && widget.contact.notes != _controller.text) {
      _controller.text = widget.contact.notes;
    }
  }

  void _save() {
    final store = CrmScope.read(context);
    final current = store.contactById(widget.contact.id);
    if (current == null || current.notes == _controller.text.trim()) return;
    store.updateContact(current.copyWith(notes: _controller.text.trim()));
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      minLines: 3,
      maxLines: 8,
      onTapOutside: (_) => _focus.unfocus(),
      decoration: inputDecoration(
        'Notes',
        widget.contact.isPrivate
            ? 'Anything worth remembering about this customer?'
            : 'Anything worth remembering about this dealer?',
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.activity, required this.dealer});

  final Activity activity;
  final Contact dealer;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.read(context);
    final now = store.now();
    final a = activity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: a.isInteraction ? sage : canvas,
              shape: BoxShape.circle,
            ),
            child: Icon(
              activityIcon(a.kind),
              size: 15,
              color: a.isInteraction ? forest : muted,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: a.isInteraction
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.kind.label} · ${formatDay(a.at, now)}',
                        style: const TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        a.message,
                        style: const TextStyle(color: ink, fontSize: 12),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${dealer.name} ${a.message}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          if (a.isInteraction)
            PopupMenuButton<String>(
              tooltip: 'Entry actions',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: muted,
              ),
              onSelected: (_) => store.deleteActivity(a.id),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: danger)),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 10),
              child: Text(
                formatAgo(a.at, now),
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
