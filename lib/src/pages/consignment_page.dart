import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/consignment_forms.dart';

enum _BikeFilter {
  atDealer('At dealers'),
  unpaid('Sold · unpaid'),
  sold('Sold'),
  returned('Returned'),
  all('All bikes');

  const _BikeFilter(this.label);
  final String label;

  bool matches(ConsignedBike b) => switch (this) {
    atDealer => b.isAtDealer,
    unpaid => b.awaitingPayment,
    sold => b.status == ConsignmentStatus.sold,
    returned => b.status == ConsignmentStatus.returned,
    all => true,
  };
}

/// Bikes placed at dealers on consignment (dépôt-vente), by frame number.
class ConsignmentPage extends StatefulWidget {
  const ConsignmentPage({super.key});

  @override
  State<ConsignmentPage> createState() => _ConsignmentPageState();
}

class _ConsignmentPageState extends State<ConsignmentPage> {
  final _search = TextEditingController();
  _BikeFilter _filter = _BikeFilter.atDealer;
  String? _dealerId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(CrmStore store) async {
    try {
      final now = store.now();
      final uri = await FilePicker.saveFile(
        fileName:
            'molenstraat-consignment-${now.year}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}.csv',
        bytes: Uint8List.fromList(utf8.encode('﻿${store.exportBikesCsv()}')),
      );
      if (uri == null && !kIsWeb) return;
      if (mounted) {
        showMessage(context, 'Exported ${store.bikes.length} bikes.');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save the file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final q = ConsignedBike.normalizeFrame(_search.text);
    final text = _search.text.trim().toLowerCase();
    final bikes =
        store.bikes.where((b) {
          if (_dealerId != null && b.contactId != _dealerId) return false;
          if (text.isNotEmpty) {
            final dealer = store.contactById(b.contactId);
            final hit =
                ConsignedBike.normalizeFrame(b.frameNumber).contains(q) ||
                '${b.model} ${dealer?.name ?? ''} ${dealer?.city ?? ''}'
                    .toLowerCase()
                    .contains(text);
            if (!hit) return false;
            // A frame-number search finds the bike whatever its status.
            return true;
          }
          return _filter.matches(b);
        }).toList()..sort((a, b) {
          final da = store.contactById(a.contactId)?.name ?? '';
          final db = store.contactById(b.contactId)?.name ?? '';
          final byDealer = da.toLowerCase().compareTo(db.toLowerCase());
          return byDealer != 0 ? byDealer : a.placedAt.compareTo(b.placedAt);
        });

    final atDealers = store.bikesAtDealers;
    final unpaid = store.bikesAwaitingPayment;
    final soldLast30 = store.bikes
        .where(
          (b) =>
              b.soldAt != null &&
              b.soldAt!.isAfter(now.subtract(const Duration(days: 30))),
        )
        .length;
    final dealersWithBikes = <String, List<ConsignedBike>>{};
    for (final b in atDealers) {
      dealersWithBikes.putIfAbsent(b.contactId, () => []).add(b);
    }
    final dealerSummary = dealersWithBikes.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Consignment',
          subtitle: 'Bikes in dépôt-vente at your dealers, by frame number.',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Export as CSV',
                onPressed: () => _export(store),
                icon: const Icon(Icons.download_rounded, color: forest),
              ),
              const SizedBox(width: 6),
              PrimaryButton(
                label: 'Place bikes',
                onPressed: () => showBikeForm(context, contactId: _dealerId),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StatsGrid(
          stats: [
            StatData(
              title: 'At dealers',
              value: '${atDealers.length}',
              subtitle:
                  'at ${dealersWithBikes.length} '
                  '${dealersWithBikes.length == 1 ? 'dealer' : 'dealers'}',
              icon: Icons.pedal_bike_rounded,
              color: forest,
              background: sage,
            ),
            StatData(
              title: 'Value at dealers',
              value: formatMoney(store.consignmentValueAtDealers),
              subtitle: 'at consignment prices',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF5675B8),
              background: const Color(0xFFEBEFF9),
            ),
            StatData(
              title: 'Sold · unpaid',
              value: formatMoney(store.consignmentAmountOwed),
              subtitle:
                  '${unpaid.length} ${unpaid.length == 1 ? 'bike' : 'bikes'} '
                  'awaiting payment',
              icon: Icons.payments_outlined,
              color: const Color(0xFFB36B35),
              background: const Color(0xFFF9EDE2),
            ),
            StatData(
              title: 'Sold (30 days)',
              value: '$soldLast30',
              subtitle: 'by your dealers',
              icon: Icons.sell_outlined,
              color: const Color(0xFF9A6EA8),
              background: const Color(0xFFF3EDF5),
            ),
          ],
        ),
        if (dealerSummary.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in dealerSummary)
                FilterChip(
                  label: Text(
                    '${store.contactById(e.key)?.name ?? '?'} · ${e.value.length}',
                  ),
                  selected: _dealerId == e.key,
                  showCheckmark: false,
                  selectedColor: sage,
                  side: const BorderSide(color: line),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _dealerId == e.key ? forest : ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (on) =>
                      setState(() => _dealerId = on ? e.key : null),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        height: 40,
                        child: TextField(
                          key: const Key('frame-search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Frame number, model or dealer',
                            hintStyle: const TextStyle(
                              color: muted,
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 19,
                            ),
                            filled: true,
                            fillColor: canvas,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      for (final f in _BikeFilter.values)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f && _search.text.isEmpty,
                          showCheckmark: false,
                          selectedColor: sage,
                          side: const BorderSide(color: line),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _filter == f ? forest : muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setState(() {
                            _filter = f;
                            _search.clear();
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: line),
              if (bikes.isEmpty)
                EmptyState(
                  icon: Icons.pedal_bike_rounded,
                  message: store.bikes.isEmpty
                      ? 'No consignment bikes yet. Use "Place bikes" to record '
                            'bikes you leave at a dealer.'
                      : _search.text.isNotEmpty
                      ? 'No bike matches "${_search.text}".'
                      : 'No bikes in this view.',
                )
              else
                for (final b in bikes) BikeRow(bike: b),
            ],
          ),
        ),
      ],
    );
  }
}
