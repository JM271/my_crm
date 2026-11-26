import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

IconData activityIcon(ActivityKind kind) => switch (kind) {
  ActivityKind.call => Icons.phone_in_talk_outlined,
  ActivityKind.visit => Icons.storefront_outlined,
  ActivityKind.email => Icons.mail_outline_rounded,
  ActivityKind.note => Icons.sticky_note_2_outlined,
  ActivityKind.system => Icons.bolt_rounded,
};

/// "How long since we last talked to this dealer", e.g. `12 days ago`.
String lastContactLabel(DateTime? last, DateTime now) {
  if (last == null) return 'No contact logged yet';
  final days = dateOnly(now).difference(dateOnly(last)).inDays;
  if (days <= 0) return 'Last contact: today';
  if (days == 1) return 'Last contact: yesterday';
  return 'Last contact: $days days ago';
}

/// Log a call, visit, email or note with a dealer.
Future<void> showLogInteraction(
  BuildContext context, {
  required String contactId,
  ActivityKind kind = ActivityKind.call,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LogDialog(
      store: CrmScope.read(context),
      contactId: contactId,
      kind: kind,
    ),
  );
}

class _LogDialog extends StatefulWidget {
  const _LogDialog({
    required this.store,
    required this.contactId,
    required this.kind,
  });

  final CrmStore store;
  final String contactId;
  final ActivityKind kind;

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  late var _kind = widget.kind;
  late var _at = widget.store.now();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = widget.store.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;
    // Keep the current time of day for today, noon for earlier days.
    final sameDay = dateOnly(picked) == dateOnly(now);
    setState(
      () => _at = sameDay
          ? now
          : DateTime(picked.year, picked.month, picked.day, 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dealer = widget.store.contactById(widget.contactId);
    return AlertDialog(
      title: Text(
        'Log ${_kind.label.toLowerCase()}${dealer == null ? '' : ' · ${dealer.name}'}',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<ActivityKind>(
                segments: [
                  for (final k in ActivityKind.logged)
                    ButtonSegment(
                      value: k,
                      icon: Icon(activityIcon(k), size: 17),
                      label: Text(k.label),
                    ),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(formatDay(_at, widget.store.now())),
              ),
              const SizedBox(height: 14),
              AppFormField(
                controller: _note,
                label: 'What happened?',
                hint: switch (_kind) {
                  ActivityKind.call => 'E.g. wants 4 E-Fatbikes for spring',
                  ActivityKind.visit => 'E.g. showroom has space for 3 bikes',
                  ActivityKind.email => 'E.g. sent price list 2027',
                  _ => 'Anything worth remembering',
                },
                maxLines: 4,
                autofocus: true,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please write a short note'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            widget.store.logInteraction(
              contactId: widget.contactId,
              kind: _kind,
              note: _note.text.trim(),
              at: _at,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
