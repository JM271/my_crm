import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';
import 'dashboard_page.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final contactTotal = store.contacts.length;
    final tasksTotal = store.tasks.length;
    final tasksDone = store.tasks.where((t) => t.done).length;

    // Customers ranked by won value.
    final wonByContact = <String, double>{};
    for (final d in store.deals.where((d) => d.stage == DealStage.gewonnen)) {
      wonByContact.update(
        d.contactId,
        (v) => v + d.value,
        ifAbsent: () => d.value,
      );
    }
    final topCustomers = wonByContact.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxStageValue = DealStage.values
        .map(store.valueInStage)
        .fold<double>(0, (a, b) => a > b ? a : b);

    final statusPanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Dealers by status',
            subtitle: '$contactTotal dealers in total',
          ),
          const SizedBox(height: 18),
          for (final s in ContactStatus.values)
            _BarRow(
              label: s.label,
              valueLabel: '${store.countWithStatus(s)}',
              fraction: contactTotal == 0
                  ? 0
                  : store.countWithStatus(s) / contactTotal,
              color: statusColors(s).$2,
            ),
        ],
      ),
    );

    final stagePanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Value by stage',
            subtitle: '${store.deals.length} deals in total',
          ),
          const SizedBox(height: 18),
          for (final s in DealStage.values)
            _BarRow(
              label: s.label,
              valueLabel:
                  '${formatMoney(store.valueInStage(s))} · ${store.countInStage(s)}',
              fraction: maxStageValue == 0
                  ? 0
                  : store.valueInStage(s) / maxStageValue,
              color: stageColor(s),
            ),
        ],
      ),
    );

    final tasksPanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Tasks',
            subtitle: '$tasksDone of $tasksTotal completed',
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: tasksTotal == 0 ? 0 : tasksDone / tasksTotal,
              color: forest,
              backgroundColor: line,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            store.urgentTaskCount == 0
                ? 'Nothing due today or earlier.'
                : '${store.urgentTaskCount} open for today or overdue.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );

    final customersPanel = Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeading(
            title: 'Top customers',
            subtitle: 'By revenue won',
          ),
          const SizedBox(height: 10),
          if (topCustomers.isEmpty)
            const EmptyState(
              icon: Icons.emoji_events_outlined,
              message: 'No deals won yet.',
            ),
          for (final entry in topCustomers.take(5))
            if (store.contactById(entry.key) case final contact?)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => openContact(context, contact.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      ContactAvatar(name: contact.name),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          contact.city.isEmpty
                              ? contact.name
                              : '${contact.name} · ${contact.city}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(entry.value),
                        style: const TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );

    // Dealers per shop type ("both" counted once, as its own bar).
    final typePanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeading(
            title: 'Dealers by type',
            subtitle: 'What your dealers sell',
          ),
          const SizedBox(height: 18),
          for (final t in ShopType.values)
            _BarRow(
              label: t == ShopType.unknown ? 'Type not set' : t.label,
              valueLabel: '${store.contacts.where((c) => c.type == t).length}',
              fraction: contactTotal == 0
                  ? 0
                  : store.contacts.where((c) => c.type == t).length /
                        contactTotal,
              color: t == ShopType.unknown ? line : forest,
            ),
        ],
      ),
    );

    final cityCounts = <String, int>{};
    for (final c in store.contacts) {
      final city = c.city.trim();
      if (city.isNotEmpty) {
        cityCounts.update(city, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final topCities = cityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCity = topCities.isEmpty ? 1 : topCities.first.value;
    final cityPanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Top cities',
            subtitle: '${cityCounts.length} cities with dealers',
          ),
          const SizedBox(height: 18),
          if (topCities.isEmpty)
            const EmptyState(
              icon: Icons.place_outlined,
              message: 'Add cities to your dealers to see this.',
            ),
          for (final e in topCities.take(8))
            _BarRow(
              label: e.key,
              valueLabel: '${e.value}',
              fraction: e.value / maxCity,
              color: const Color(0xFF5D9274),
            ),
        ],
      ),
    );

    final sales = store.wonProductSales();
    final productsPanel = Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(
            title: 'Products sold',
            subtitle:
                '${sales.fold(0, (n, s) => n + s.units)} units in won deals',
          ),
          const SizedBox(height: 10),
          if (sales.isEmpty)
            const EmptyState(
              icon: Icons.pedal_bike_rounded,
              message: 'Add order lines to won deals to see product sales.',
            ),
          for (final sale in sales.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.pedal_bike_rounded, size: 18, color: forest),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      sale.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${sale.units} × · ${formatMoney(sale.revenue)}',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Reports',
          subtitle: 'Insight into how your network is growing.',
        ),
        const SizedBox(height: 24),
        StatsGrid(stats: overviewStats(store)),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 820) {
              return Column(
                children: [
                  for (final p in [
                    statusPanel,
                    stagePanel,
                    typePanel,
                    cityPanel,
                    productsPanel,
                    tasksPanel,
                    customersPanel,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: p,
                    ),
                ],
              );
            }
            return Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: statusPanel),
                      const SizedBox(width: 18),
                      Expanded(child: stagePanel),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: typePanel),
                      const SizedBox(width: 18),
                      Expanded(child: cityPanel),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: productsPanel),
                    const SizedBox(width: 18),
                    Expanded(child: customersPanel),
                  ],
                ),
                const SizedBox(height: 18),
                tasksPanel,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.valueLabel,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: ink, fontSize: 12),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: fraction.clamp(0, 1),
              color: color,
              backgroundColor: canvas,
            ),
          ),
        ],
      ),
    );
  }
}
