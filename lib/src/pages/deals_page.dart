import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import '../widgets/rows.dart';
import 'products_page.dart';

class DealsPage extends StatelessWidget {
  const DealsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final lost = store.deals
        .where((d) => d.stage == DealStage.verloren)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Deals',
          subtitle: 'From first conversation to a great partnership.',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Products',
                onPressed: () => openProducts(context),
                icon: const Icon(Icons.pedal_bike_rounded, color: forest),
              ),
              const SizedBox(width: 6),
              PrimaryButton(
                label: 'New deal',
                onPressed: () => showDealForm(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const PipelineCard(),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = [
              for (final s in DealStage.pipeline) _StageColumn(stage: s),
            ];
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  for (final c in columns) ...[c, const SizedBox(height: 14)],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: columns[i]),
                ],
              ],
            );
          },
        ),
        if (lost.isNotEmpty) ...[
          const SizedBox(height: 18),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  'Lost deals (${lost.length})',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  formatMoney(store.valueInStage(DealStage.verloren)),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
                children: [for (final d in lost) DealTile(deal: d)],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({required this.stage});

  final DealStage stage;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final deals = store.deals.where((d) => d.stage == stage).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: stageColor(stage)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Tag(
                  label: '${deals.length}',
                  background: canvas,
                  foreground: muted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(store.valueInStage(stage)),
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: line),
          if (deals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No deals',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          for (final d in deals) DealTile(deal: d, showStage: false),
        ],
      ),
    );
  }
}
