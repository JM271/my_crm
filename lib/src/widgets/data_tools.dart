import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../theme.dart';
import 'common.dart';

String _dateStamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<void> _save(
  BuildContext context, {
  required String fileName,
  required String content,
  required String successMessage,
}) async {
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    // On desktop, null means the save dialog was cancelled. On the web the
    // browser downloads the file directly.
    if (uri == null && !kIsWeb) return;
    if (context.mounted) showMessage(context, successMessage);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not save the file: $e');
  }
}

/// Saves all dealers as a CSV file (re-importable, opens in Excel).
Future<void> exportDealers(BuildContext context) {
  final store = CrmScope.read(context);
  return _save(
    context,
    fileName: 'molenstraat-dealers-${_dateStamp(store.now())}.csv',
    // BOM so Excel opens umlauts (ü, é) correctly.
    content: '﻿${store.exportDealersCsv()}',
    successMessage: 'Exported ${store.contacts.length} dealers.',
  );
}

/// Saves a full backup (dealers, deals, tasks, activity, products, settings).
Future<void> backupData(BuildContext context) {
  final store = CrmScope.read(context);
  return _save(
    context,
    fileName: 'molenstraat-crm-backup-${_dateStamp(store.now())}.json',
    content: store.exportBackup(),
    successMessage: 'Backup saved.',
  );
}

/// Replaces all data with a backup file, after confirmation.
Future<void> restoreData(BuildContext context) async {
  final store = CrmScope.read(context);
  final file = await FilePicker.pickFile(
    dialogTitle: 'Restore backup',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null || !context.mounted) return;
  final ok = await confirmDelete(
    context,
    title: 'Restore this backup?',
    message:
        'All current data will be replaced with the contents of '
        '${file.name}. Make a backup first if you want to keep it.',
    actionLabel: 'Restore',
  );
  if (!ok || !context.mounted) return;
  try {
    final raw = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    store.restoreBackup(raw);
    if (context.mounted) {
      showMessage(
        context,
        'Backup restored: ${store.contacts.length} dealers, '
        '${store.deals.length} deals.',
      );
    }
  } on FormatException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

Future<void> showSettingsDialog(BuildContext context) {
  final store = CrmScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(store: store),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.store});

  final CrmStore store;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _name = TextEditingController(text: widget.store.userName);
  late var _currency = widget.store.currency;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Settings',
        style: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFormField(controller: _name, label: 'Your name'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: inputDecoration('Currency'),
              items: const [
                DropdownMenuItem(
                  value: 'CHF',
                  child: Text('Swiss franc (CHF)'),
                ),
                DropdownMenuItem(value: 'EUR', child: Text('Euro (€)')),
              ],
              onChanged: (c) => setState(() => _currency = c ?? _currency),
            ),
            const SizedBox(height: 10),
            const Text(
              'Changing the currency only changes the symbol. Amounts are not '
              'converted.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
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
            widget.store.updateSettings(
              userName: _name.text,
              currency: _currency,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Shows "CHF" or "€" for labels such as "Value (CHF)".
String get currencyLabel => moneyCurrency == 'EUR' ? '€' : 'CHF';
