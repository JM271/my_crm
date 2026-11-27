import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'data_tools.dart';
import 'forms.dart';
import 'rows.dart';

const _frameStyle = TextStyle(
  fontFamily: 'monospace',
  fontWeight: FontWeight.w700,
  letterSpacing: 0.3,
);

/// Status chip for a consignment bike.
class BikeStatusTag extends StatelessWidget {
  const BikeStatusTag({super.key, required this.bike});

  final ConsignedBike bike;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (bike.status) {
      ConsignmentStatus.atDealer => ('At dealer', sage, forest),
      ConsignmentStatus.sold when !bike.paid => (
        'Sold · unpaid',
        const Color(0xFFF9EFE4),
        const Color(0xFFAE733B),
      ),
      ConsignmentStatus.sold => (
        'Sold · paid',
        const Color(0xFFE8F1EB),
        const Color(0xFF397452),
      ),
      ConsignmentStatus.returned => ('Returned', canvas, muted),
    };
    return Tag(label: label, background: bg, foreground: fg);
  }
}

/// One consignment bike in a list.
class BikeRow extends StatelessWidget {
  const BikeRow({super.key, required this.bike, this.showDealer = true});

  final ConsignedBike bike;
  final bool showDealer;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final now = store.now();
    final dealer = store.contactById(bike.contactId);
    final since = switch (bike.status) {
      ConsignmentStatus.atDealer =>
        'since ${formatDay(bike.placedAt, now)} · '
            '${dateOnly(now).difference(dateOnly(bike.placedAt)).inDays} days',
      ConsignmentStatus.sold => 'sold ${formatDay(bike.soldAt!, now)}',
      ConsignmentStatus.returned =>
        'returned ${formatDay(bike.returnedAt!, now)}',
    };
    final subtitle = [
      bike.model,
      if (showDealer && dealer != null) dealer.name,
      since,
    ].join(' · ');
    final price = Text(
      formatMoney(bike.price),
      style: const TextStyle(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
    return InkWell(
      onTap: () => showBikeDetails(context, bike.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 11, 6, 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // On phones, price and status go on a second line.
            final narrow = constraints.maxWidth < 480;
            return Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bike.isAtDealer ? sage : canvas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.pedal_bike_rounded,
                    size: 19,
                    color: bike.isAtDealer ? forest : muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bike.frameNumber,
                        overflow: TextOverflow.ellipsis,
                        style: _frameStyle.copyWith(color: ink, fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: narrow ? 2 : 1,
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                      if (narrow) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            BikeStatusTag(bike: bike),
                            const SizedBox(width: 10),
                            price,
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 8),
                  price,
                  const SizedBox(width: 10),
                  BikeStatusTag(bike: bike),
                ],
                BikeMenu(bike: bike),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Actions for one bike (sell, return, move, paid, edit, delete).
class BikeMenu extends StatelessWidget {
  const BikeMenu({super.key, required this.bike});

  final ConsignedBike bike;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Bike actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 20, color: muted),
      onSelected: (action) => runBikeAction(context, bike, action),
      itemBuilder: (_) => [
        if (bike.isAtDealer) ...const [
          PopupMenuItem(value: 'sold', child: Text('Mark as sold')),
          PopupMenuItem(value: 'returned', child: Text('Mark as returned')),
          PopupMenuItem(value: 'move', child: Text('Move to another dealer')),
        ],
        if (bike.status == ConsignmentStatus.sold)
          PopupMenuItem(
            value: 'paid',
            child: Text(bike.paid ? 'Mark as not paid' : 'Payment received'),
          ),
        if (bike.status == ConsignmentStatus.returned)
          const PopupMenuItem(value: 'move', child: Text('Place at a dealer')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'details', child: Text('Details & history')),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: danger)),
        ),
      ],
    );
  }
}

Future<void> runBikeAction(
  BuildContext context,
  ConsignedBike bike,
  String action,
) async {
  final store = CrmScope.read(context);
  switch (action) {
    case 'sold':
      await showSellBikeDialog(context, bike);
    case 'returned':
      final at = await _pickDay(context, store, title: 'Returned on');
      if (at != null) store.markBikeReturned(bike.id, at: at);
    case 'move':
      await showMoveBikeDialog(context, bike);
    case 'paid':
      store.setBikePaid(bike.id, !bike.paid);
    case 'details':
      await showBikeDetails(context, bike.id);
    case 'edit':
      await showBikeForm(context, existing: bike);
    case 'delete':
      final ok = await confirmDelete(
        context,
        title: 'Delete bike ${bike.frameNumber}?',
        message:
            'The bike and its history will be removed. Use "Mark as returned" '
            'instead if the bike came back to you.',
      );
      if (ok) store.deleteBike(bike.id);
  }
}

/// Date picker that defaults to today and allows no future dates.
Future<DateTime?> _pickDay(
  BuildContext context,
  CrmStore store, {
  required String title,
}) async {
  final now = store.now();
  final picked = await showDatePicker(
    context: context,
    helpText: title,
    initialDate: now,
    firstDate: DateTime(2020),
    lastDate: now,
  );
  if (picked == null) return null;
  return dateOnly(picked) == dateOnly(now)
      ? now
      : DateTime(picked.year, picked.month, picked.day, 12);
}

// ------------------------------------------------------------ place / edit

/// Places new bikes at a dealer (any mix of models), or edits one bike.
Future<void> showBikeForm(
  BuildContext context, {
  ConsignedBike? existing,
  String? contactId,
}) {
  final store = CrmScope.read(context);
  if (existing == null && store.contacts.isEmpty) {
    showMessage(context, 'Add a dealer first.');
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (_) => existing == null
        ? _PlaceBikesForm(store: store, contactId: contactId)
        : _EditBikeForm(store: store, bike: existing),
  );
}

/// Model names offered in the forms: the consignment models, plus [current]
/// when an older bike has a model that is not in the list any more.
List<String> _modelNames([String? current]) => [
  for (final m in consignmentModels) m.name,
  if (current != null &&
      current.isNotEmpty &&
      !consignmentModels.any((m) => m.name == current))
    current,
];

/// Retail price of a consignment model.
double? _modelPrice(String model) {
  for (final m in consignmentModels) {
    if (m.name == model) return m.price;
  }
  return null;
}

/// Dépôt-vente margin of the dealer [contactId].
double _depotMargin(CrmStore store, String? contactId) =>
    store.contactById(contactId)?.effectiveDepotMargin ??
    Contact.defaultDepotMargin;

/// One bike being placed: its model, frame number and price.
class _BikeLine {
  _BikeLine(this.model, double this.retail, double margin)
    : price = TextEditingController(
        text: formatAmount(partnerPrice(retail, margin)),
      );

  String model;

  /// Retail price the dealer's price was worked out from. Null once the
  /// price was typed by hand: then it is left alone.
  double? retail;
  final frame = TextEditingController();
  final TextEditingController price;
  final focus = FocusNode();

  void dispose() {
    frame.dispose();
    price.dispose();
    focus.dispose();
  }
}

class _PlaceBikesForm extends StatefulWidget {
  const _PlaceBikesForm({required this.store, this.contactId});

  final CrmStore store;
  final String? contactId;

  @override
  State<_PlaceBikesForm> createState() => _PlaceBikesFormState();
}

class _PlaceBikesFormState extends State<_PlaceBikesForm> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final List<_BikeLine> _lines = [];
  late String? _contactId = widget.contactId;
  late DateTime _placedAt = widget.store.now();
  bool _dealerMissing = false;
  bool _noBikes = false;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _margin => _depotMargin(widget.store, _contactId);

  /// Works the prices out again for another dealer, except those typed in.
  void _reprice() {
    for (final l in _lines) {
      if (l.retail != null) {
        l.price.text = formatAmount(partnerPrice(l.retail!, _margin));
      }
    }
  }

  void _add(String model, double retail) {
    final line = _BikeLine(model, retail, _margin);
    setState(() {
      _lines.add(line);
      _noBikes = false;
    });
    // Straight to the frame number of the new bike.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) line.focus.requestFocus();
    });
  }

  void _remove(_BikeLine line) {
    setState(() => _lines.remove(line));
    line.dispose();
  }

  double get _total =>
      _lines.fold(0, (sum, l) => sum + (parseMoney(l.price.text) ?? 0));

  String? _validateFrame(_BikeLine line) {
    final f = line.frame.text.trim();
    if (f.isEmpty) return 'Frame number?';
    final key = ConsignedBike.normalizeFrame(f);
    final first = _lines.firstWhere(
      (l) => ConsignedBike.normalizeFrame(l.frame.text.trim()) == key,
    );
    if (!identical(first, line)) return 'Entered twice';
    final clash = widget.store.bikeByFrame(f);
    if (clash != null) {
      final where = widget.store.contactById(clash.contactId)?.name ?? '?';
      return 'Already exists ($where)';
    }
    return null;
  }

  void _submit() {
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _dealerMissing = _contactId == null;
      _noBikes = _lines.isEmpty;
    });
    if (!formOk || _contactId == null || _lines.isEmpty) return;
    final store = widget.store;
    final placed = store.placeBikeBatch(
      contactId: _contactId!,
      bikes: [
        for (final l in _lines)
          (
            frameNumber: l.frame.text.trim(),
            model: l.model,
            productId: store.productForModel(l.model)?.id,
            price: parseMoney(l.price.text) ?? 0,
          ),
      ],
      placedAt: _placedAt,
      notes: _notes.text.trim(),
    );
    Navigator.pop(context);
    showMessage(
      context,
      '${placed.length} ${placed.length == 1 ? 'bike' : 'bikes'} placed at '
      '${store.contactById(_contactId)?.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final count = _lines.length;
    return AlertDialog(
      title: const Text(
        'Place bikes on consignment',
        style: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DealerPicker(
                  store: store,
                  selectedId: _contactId,
                  errorText: _dealerMissing ? 'Choose a dealer' : null,
                  onSelected: (id) => setState(() {
                    _contactId = id;
                    _dealerMissing = false;
                    _reprice();
                  }),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add bikes',
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a model once per bike. The price is what the dealer '
                  'pays: retail minus their ${formatMargin(_margin)} margin.',
                  style: TextStyle(
                    color: _noBikes ? danger : muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in consignmentModels)
                      ActionChip(
                        key: Key('add-${m.name}'),
                        avatar: const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: forest,
                        ),
                        label: Text(
                          '${m.name} · '
                          '${formatMoney(partnerPrice(m.price, _margin))}',
                        ),
                        labelStyle: const TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: sage,
                        side: BorderSide.none,
                        onPressed: () => _add(m.name, m.price),
                      ),
                  ],
                ),
                for (var i = 0; i < _lines.length; i++) ...[
                  const SizedBox(height: 12),
                  _BikeLineEditor(
                    key: ObjectKey(_lines[i]),
                    index: i + 1,
                    bike: _lines[i],
                    margin: _margin,
                    validateFrame: () => _validateFrame(_lines[i]),
                    onChanged: () => setState(() {}),
                    onRemove: () => _remove(_lines[i]),
                  ),
                ],
                if (count > 0) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$count ${count == 1 ? 'bike' : 'bikes'}',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ),
                      Text(
                        formatMoney(_total),
                        style: const TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () async {
                    final at = await _pickDay(
                      context,
                      store,
                      title: 'Placed on',
                    );
                    if (at != null) setState(() => _placedAt = at);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('Placed ${formatDay(_placedAt, store.now())}'),
                ),
                const SizedBox(height: 14),
                AppFormField(controller: _notes, label: 'Notes', maxLines: 2),
              ],
            ),
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
          onPressed: _submit,
          child: Text(count <= 1 ? 'Place bike' : 'Place $count bikes'),
        ),
      ],
    );
  }
}

/// Model, frame number and price of one bike, stacked so it fits on a phone.
class _BikeLineEditor extends StatelessWidget {
  const _BikeLineEditor({
    super.key,
    required this.index,
    required this.bike,
    required this.margin,
    required this.validateFrame,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _BikeLine bike;
  final double margin;
  final String? Function() validateFrame;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '$index',
                style: const TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: bike.model,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  items: [
                    for (final name in _modelNames(bike.model))
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (name) {
                    if (name == null) return;
                    bike.model = name;
                    final retail = _modelPrice(name);
                    if (retail != null) {
                      bike.retail = retail;
                      bike.price.text = formatAmount(
                        partnerPrice(retail, margin),
                      );
                    }
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove bike',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18, color: muted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: bike.frame,
                    focusNode: bike.focus,
                    style: _frameStyle.copyWith(fontSize: 14),
                    textInputAction: TextInputAction.next,
                    decoration: inputDecoration('Frame number')
                        .copyWith(fillColor: Colors.white),
                    validator: (_) => validateFrame(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 104,
                  child: TextFormField(
                    controller: bike.price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: inputDecoration(currencyLabel)
                        .copyWith(fillColor: Colors.white),
                    onChanged: (_) {
                      bike.retail = null;
                      onChanged();
                    },
                    validator: (v) =>
                        parseMoney(v ?? '') == null ? 'Price?' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditBikeForm extends StatefulWidget {
  const _EditBikeForm({required this.store, required this.bike});

  final CrmStore store;
  final ConsignedBike bike;

  @override
  State<_EditBikeForm> createState() => _EditBikeFormState();
}

class _EditBikeFormState extends State<_EditBikeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _frame = TextEditingController(text: widget.bike.frameNumber);
  late final _price = TextEditingController(
    text: formatAmount(widget.bike.price),
  );
  late final _notes = TextEditingController(text: widget.bike.notes);
  late String _model = widget.bike.model;

  @override
  void dispose() {
    for (final c in [_frame, _price, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateFrame(String? v) {
    final f = v?.trim() ?? '';
    if (f.isEmpty) return 'Please enter a frame number';
    final clash = widget.store.bikeByFrame(f, exceptId: widget.bike.id);
    if (clash != null) {
      final where = widget.store.contactById(clash.contactId)?.name ?? '?';
      return '$f already exists (${clash.status.label.toLowerCase()}, $where)';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final store = widget.store;
    final productId = _model == widget.bike.model
        ? widget.bike.productId
        : store.productForModel(_model)?.id;
    store.updateBike(
      widget.bike.copyWith(
        frameNumber: _frame.text.trim(),
        model: _model,
        productId: () => productId,
        price: parseMoney(_price.text) ?? 0,
        notes: _notes.text.trim(),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Edit bike',
        style: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  isExpanded: true,
                  decoration: inputDecoration('Model'),
                  items: [
                    for (final name in _modelNames(widget.bike.model))
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (name) => setState(() {
                    _model = name ?? _model;
                    final retail = _modelPrice(_model);
                    if (retail != null) {
                      _price.text = formatAmount(
                        partnerPrice(
                          retail,
                          _depotMargin(widget.store, widget.bike.contactId),
                        ),
                      );
                    }
                  }),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _frame,
                  style: _frameStyle.copyWith(fontSize: 14),
                  decoration: inputDecoration('Frame number'),
                  validator: _validateFrame,
                ),
                const SizedBox(height: 14),
                AppFormField(
                  controller: _price,
                  label: 'Price per bike ($currencyLabel)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) =>
                      parseMoney(v ?? '') == null ? 'Enter a price' : null,
                ),
                const SizedBox(height: 14),
                AppFormField(controller: _notes, label: 'Notes', maxLines: 2),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

// -------------------------------------------------------------------- sell

Future<void> showSellBikeDialog(BuildContext context, ConsignedBike bike) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SellDialog(store: CrmScope.read(context), bike: bike),
  );
}

class _SellDialog extends StatefulWidget {
  const _SellDialog({required this.store, required this.bike});

  final CrmStore store;
  final ConsignedBike bike;

  @override
  State<_SellDialog> createState() => _SellDialogState();
}

class _SellDialogState extends State<_SellDialog> {
  final _salePrice = TextEditingController();
  late DateTime _at = widget.store.now();
  bool _paid = false;

  @override
  void dispose() {
    _salePrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final bike = widget.bike;
    return AlertDialog(
      title: Text(
        'Sold: ${bike.frameNumber}',
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${bike.model} · ${store.contactById(bike.contactId)?.name ?? ''}\n'
              'Dealer owes you ${formatMoney(bike.price)}.',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final at = await _pickDay(context, store, title: 'Sold on');
                if (at != null) setState(() => _at = at);
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Sold ${formatDay(_at, store.now()).toLowerCase()}'),
            ),
            const SizedBox(height: 14),
            AppFormField(
              controller: _salePrice,
              label: 'Sold to customer for (optional)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _paid,
              onChanged: (v) => setState(() => _paid = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: forest,
              title: const Text('Dealer has already paid'),
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
            store.markBikeSold(
              bike.id,
              at: _at,
              salePrice: parseMoney(_salePrice.text),
            );
            if (_paid) store.setBikePaid(bike.id, true);
            Navigator.pop(context);
          },
          child: const Text('Mark as sold'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- move

Future<void> showMoveBikeDialog(BuildContext context, ConsignedBike bike) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MoveDialog(store: CrmScope.read(context), bike: bike),
  );
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.store, required this.bike});

  final CrmStore store;
  final ConsignedBike bike;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String? _to;
  late DateTime _at = widget.store.now();
  bool _missing = false;

  /// The bike's price at the new dealer: their rate, when the price followed
  /// the old dealer's rate. A price agreed by hand stays.
  double get _newPrice {
    final bike = widget.bike;
    final retail = _modelPrice(bike.model);
    if (retail == null || _to == null) return bike.price;
    final store = widget.store;
    final followedRate =
        bike.price == partnerPrice(retail, _depotMargin(store, bike.contactId));
    return followedRate
        ? partnerPrice(retail, _depotMargin(store, _to))
        : bike.price;
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final bike = widget.bike;
    return AlertDialog(
      title: Text(
        bike.isAtDealer
            ? 'Move ${bike.frameNumber}'
            : 'Place ${bike.frameNumber}',
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bike.isAtDealer)
              Text(
                'Now at ${store.contactById(bike.contactId)?.name ?? '?'}',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            const SizedBox(height: 14),
            DealerPicker(
              store: store,
              selectedId: _to,
              errorText: _missing ? 'Choose a dealer' : null,
              onSelected: (id) => setState(() {
                _to = id;
                _missing = false;
              }),
            ),
            if (_to != null && _newPrice != bike.price) ...[
              const SizedBox(height: 8),
              Text(
                'New price: ${formatMoney(_newPrice)} '
                '(retail minus ${formatMargin(_depotMargin(store, _to))} '
                'margin, was ${formatMoney(bike.price)})',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final at = await _pickDay(context, store, title: 'Moved on');
                if (at != null) setState(() => _at = at);
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(formatDay(_at, store.now())),
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
            if (_to == null || (_to == bike.contactId && bike.isAtDealer)) {
              setState(() => _missing = true);
              return;
            }
            store.moveBike(bike.id, _to!, at: _at, price: _newPrice);
            Navigator.pop(context);
          },
          child: Text(bike.isAtDealer ? 'Move bike' : 'Place bike'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- details

Future<void> showBikeDetails(BuildContext context, String bikeId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BikeDetails(bikeId: bikeId),
  );
}

class _BikeDetails extends StatelessWidget {
  const _BikeDetails({required this.bikeId});

  final String bikeId;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final bike = store.bikeById(bikeId);
    if (bike == null) {
      return AlertDialog(
        content: const Text('This bike no longer exists.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final now = store.now();
    final dealer = store.contactById(bike.contactId);
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: ink, fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: SelectableText(
              bike.frameNumber,
              style: _frameStyle.copyWith(color: ink, fontSize: 18),
            ),
          ),
          BikeStatusTag(bike: bike),
          BikeMenu(bike: bike),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line('Model', bike.model),
              line(
                bike.isAtDealer ? 'At dealer' : 'Last dealer',
                [
                  dealer?.name ?? '?',
                  if (dealer != null && dealer.city.isNotEmpty) dealer.city,
                ].join(' · '),
              ),
              line('Placed', formatDay(bike.placedAt, now)),
              line('Price', formatMoney(bike.price)),
              if (bike.soldAt != null)
                line('Sold', formatDay(bike.soldAt!, now)),
              if (bike.salePrice != null)
                line('Sold for', formatMoney(bike.salePrice!)),
              if (bike.status == ConsignmentStatus.sold)
                line('Paid', bike.paid ? 'Yes' : 'Not yet'),
              if (bike.returnedAt != null)
                line('Returned', formatDay(bike.returnedAt!, now)),
              if (bike.notes.isNotEmpty) line('Notes', bike.notes),
              const SizedBox(height: 14),
              const Text(
                'History',
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final e in bike.history.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 7,
                        color: Color(0xFF9EBD9C),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.text,
                          style: const TextStyle(color: ink, fontSize: 12),
                        ),
                      ),
                      Text(
                        formatDay(e.at, now),
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (dealer != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openContact(context, dealer.id);
            },
            child: const Text('Open dealer'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
