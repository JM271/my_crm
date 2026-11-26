import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';

enum DealerSort {
  newest('Recently added'),
  name('Name A–Z'),
  city('City'),
  followUp('Longest since contact');

  const DealerSort(this.label);
  final String label;
}

/// Search, filter and sort state owned by the shell, shared by pages.
class ContactFilter {
  const ContactFilter({
    required this.query,
    required this.status,
    required this.onStatusChanged,
    this.type,
    this.onTypeChanged,
    this.sort = DealerSort.newest,
    this.onSortChanged,
  });

  final DealerSort sort;
  final ValueChanged<DealerSort>? onSortChanged;

  final String query;

  /// null = all dealers.
  final ContactStatus? status;
  final ValueChanged<ContactStatus?> onStatusChanged;

  /// null = any type.
  final ShopType? type;
  final ValueChanged<ShopType?>? onTypeChanged;

  bool get isActive => query.isNotEmpty || status != null || type != null;

  List<Contact> apply(
    List<Contact> contacts, {
    DateTime? Function(String id)? lastContact,
  }) {
    final q = query.trim().toLowerCase();
    final result = contacts.where((c) {
      final matchesQuery =
          q.isEmpty ||
          '${c.name} ${c.contactPerson} ${c.street} ${c.postalCode} '
                  '${c.city} ${c.email} ${c.phone} ${c.website}'
              .toLowerCase()
              .contains(q);
      final matchesStatus = status == null || c.status == status;
      final matchesType =
          type == null ||
          c.isPrivate || // private customers have no shop type
          c.type == type ||
          // "Both" shops also count for e-bikes and for trottinettes.
          (c.type == ShopType.both &&
              (type == ShopType.ebike || type == ShopType.trottinette));
      return matchesQuery && matchesStatus && matchesType;
    }).toList();
    switch (sort) {
      case DealerSort.newest:
        break; // the store keeps newest first
      case DealerSort.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case DealerSort.city:
        result.sort((a, b) {
          // Dealers without a city go last.
          if (a.city.isEmpty != b.city.isEmpty) return a.city.isEmpty ? 1 : -1;
          final byCity = a.city.toLowerCase().compareTo(b.city.toLowerCase());
          return byCity != 0
              ? byCity
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case DealerSort.followUp:
        // Never contacted first, then the longest ago.
        final last = {for (final c in result) c.id: lastContact?.call(c.id)};
        result.sort((a, b) {
          final la = last[a.id], lb = last[b.id];
          if (la == null && lb == null) return 0;
          if (la == null) return -1;
          if (lb == null) return 1;
          return la.compareTo(lb);
        });
    }
    return result;
  }
}

class ContactsPage extends StatelessWidget {
  const ContactsPage({
    super.key,
    required this.contacts,
    required this.filter,
    required this.kind,
    required this.onKindChanged,
    required this.onAddContact,
    required this.onImport,
  });

  /// The dealers or private customers to list, already filtered.
  final List<Contact> contacts;
  final ContactFilter filter;
  final ContactKind kind;
  final ValueChanged<ContactKind> onKindChanged;
  final VoidCallback onAddContact;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final private = kind == ContactKind.person;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: private ? 'Private customers' : 'Your dealers',
          subtitle: private
              ? 'People who buy from Molenstraat directly.'
              : 'E-bike and trottinette shops across Switzerland.',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (private)
                const SizedBox.shrink()
              else if (MediaQuery.sizeOf(context).width < 680)
                IconButton(
                  tooltip: 'Import dealers',
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_rounded, color: forest),
                )
              else
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Import'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: forest,
                    side: const BorderSide(color: line),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              if (!private) const SizedBox(width: 10),
              PrimaryButton(
                label: private ? 'New customer' : 'New dealer',
                onPressed: onAddContact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SegmentedButton<ContactKind>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: ContactKind.dealer,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: Text('Dealers (${store.contacts.length})'),
            ),
            ButtonSegment(
              value: ContactKind.person,
              icon: const Icon(Icons.person_outline_rounded, size: 18),
              label: Text('Private (${store.privateCustomers.length})'),
            ),
          ],
          selected: {kind},
          onSelectionChanged: (s) => onKindChanged(s.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: sage,
            selectedForegroundColor: forest,
          ),
        ),
        const SizedBox(height: 18),
        if (!private) ...[
          StatsGrid(
            stats: [
              StatData(
                title: 'All dealers',
                value: '${store.contacts.length}',
                subtitle: '+${store.contactsAddedThisMonth} this month',
                icon: Icons.storefront_outlined,
                color: forest,
                background: sage,
              ),
              for (final s in ContactStatus.values)
                StatData(
                  title: switch (s) {
                    ContactStatus.klant => 'Customers',
                    ContactStatus.lead => 'Leads',
                    ContactStatus.partner => 'Partners',
                    ContactStatus.depotVente => 'Dépôt-vente',
                  },
                  value: '${store.countWithStatus(s)}',
                  subtitle: store.contacts.isEmpty
                      ? 'No dealers yet'
                      : '${(store.countWithStatus(s) * 100 / store.contacts.length).round()}% of your dealers',
                  icon: switch (s) {
                    ContactStatus.klant => Icons.handshake_outlined,
                    ContactStatus.lead => Icons.bolt_rounded,
                    ContactStatus.partner => Icons.workspace_premium_outlined,
                    ContactStatus.depotVente => Icons.pedal_bike_outlined,
                  },
                  color: statusColors(s).$2,
                  background: statusColors(s).$1,
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        ContactList(
          contacts: contacts,
          totalCount: contacts.length,
          filter: filter,
          kind: kind,
          showAll: true,
        ),
      ],
    );
  }
}

class ContactList extends StatelessWidget {
  const ContactList({
    super.key,
    required this.contacts,
    required this.totalCount,
    required this.filter,
    this.kind = ContactKind.dealer,
    this.showAll = false,
  });

  final List<Contact> contacts;
  final int totalCount;
  final ContactFilter filter;
  final ContactKind kind;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final label = filter.status?.label ?? 'Any status';
    final private = kind == ContactKind.person;
    final noun = private ? 'customer' : 'dealer';
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '$totalCount ${totalCount == 1 ? noun : '${noun}s'}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (filter.onTypeChanged != null && !private)
                        _FilterMenu<ShopType?>(
                          tooltip: 'Filter by what they sell',
                          label: filter.type?.label ?? 'Sells anything',
                          onSelected: filter.onTypeChanged!,
                          items: [
                            (null, 'Sells anything'),
                            (ShopType.ebike, 'E-bikes'),
                            (ShopType.trottinette, 'Trottinettes'),
                            (ShopType.both, 'Both'),
                            (ShopType.unknown, 'Type not set'),
                          ],
                        ),
                      _FilterMenu<ContactStatus?>(
                        tooltip: 'Filter by status',
                        label: label,
                        onSelected: filter.onStatusChanged,
                        items: [
                          (null, 'Any status'),
                          for (final s in ContactStatus.optionsFor(kind))
                            (s, s.label),
                        ],
                      ),
                      if (filter.onSortChanged != null)
                        _FilterMenu<DealerSort>(
                          tooltip: 'Sort',
                          label: 'Sort: ${filter.sort.label}',
                          onSelected: filter.onSortChanged!,
                          items: [
                            for (final s in DealerSort.values) (s, s.label),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: line),
          if (contacts.isEmpty)
            EmptyState(
              icon: private
                  ? Icons.person_outline_rounded
                  : Icons.store_outlined,
              message: filter.query.isNotEmpty
                  ? 'No ${noun}s found for "${filter.query}".'
                  : filter.isActive
                  ? 'No ${noun}s match these filters.'
                  : private
                  ? 'No private customers yet. Add one here or straight '
                        'from a new deal.'
                  : 'No dealers yet. Add one or import them from HubSpot.',
            )
          else
            for (final c in contacts) ContactRow(contact: c, compact: !showAll),
        ],
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.tooltip,
    required this.label,
    required this.onSelected,
    required this.items,
  });

  final String tooltip;
  final String label;
  final ValueChanged<T> onSelected;
  final List<(T, String)> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (value, text) in items)
          PopupMenuItem(value: value, child: Text(text)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: canvas,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}
