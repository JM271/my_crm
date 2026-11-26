import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../contact_import.dart';
import '../crm_store.dart';
import '../theme.dart';
import 'common.dart';

/// Lets the user pick a CSV (e.g. a HubSpot contacts export), shows a preview
/// and imports on confirmation. Returns true when contacts were imported.
Future<bool> importContactsFromCsv(BuildContext context) async {
  final store = CrmScope.read(context);
  final file = await FilePicker.pickFile(
    dialogTitle: 'Import dealers',
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
  if (file == null || !context.mounted) return false;

  final List<ContactDraft> drafts;
  try {
    drafts = contactsFromCsv(await file.readAsBytes());
  } on CsvImportException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  } catch (_) {
    if (context.mounted) showMessage(context, 'Could not read ${file.name}.');
    return false;
  }
  if (!context.mounted) return false;
  if (drafts.isEmpty) {
    showMessage(context, 'No dealers found in ${file.name}.');
    return false;
  }

  final source = file.name.toLowerCase().contains('hubspot')
      ? 'HubSpot'
      : 'CSV';
  final preview = store.previewImport(drafts);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(
        'Import dealers',
        style: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name, style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 14),
            Text(
              '${drafts.length} dealers found: ${preview.added} new'
              '${preview.updated > 0 ? ', ${preview.updated} already in your CRM' : ''}.',
              style: const TextStyle(color: ink, fontSize: 14),
            ),
            if (preview.updated > 0) ...[
              const SizedBox(height: 6),
              const Text(
                'Dealers already in the app (same shop name) are not '
                'duplicated. '
                'Only their empty fields are filled in.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(11),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  for (final d in drafts.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          ContactAvatar(name: d.name, radius: 14),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              d.city.isEmpty ? d.name : '${d.name} · ${d.city}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ink, fontSize: 12),
                            ),
                          ),
                          StatusTag(status: d.status),
                        ],
                      ),
                    ),
                  if (drafts.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Text(
                        '+ ${drafts.length - 5} more',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Import ${drafts.length} dealers'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final result = store.importContacts(drafts, source: source);
  showMessage(
    context,
    'Imported ${result.added} new dealers'
    '${result.updated > 0 ? ' (${result.updated} updated)' : ''}.',
  );
  return true;
}
