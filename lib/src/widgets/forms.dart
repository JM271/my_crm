import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'data_tools.dart';

// Each form opens a dialog, writes the result to the store, and returns the
// created/updated record (or null if cancelled).

/// New or existing dealer, or a private customer with [kind] (ignored when
/// editing: an existing contact keeps its kind). A new contact starts with
/// [initialName] filled in.
Future<Contact?> showContactForm(
  BuildContext context, {
  Contact? existing,
  ContactKind kind = ContactKind.dealer,
  String? initialName,
}) {
  return showDialog<Contact>(
    context: context,
    builder: (_) => _ContactForm(
      store: CrmScope.read(context),
      existing: existing,
      kind: existing?.kind ?? kind,
      initialName: initialName,
    ),
  );
}

Future<Deal?> showDealForm(
  BuildContext context, {
  Deal? existing,
  String? contactId,
}) async {
  final store = CrmScope.read(context);
  return showDialog<Deal>(
    context: context,
    builder: (_) =>
        _DealForm(store: store, existing: existing, contactId: contactId),
  );
}

Future<Task?> showTaskForm(
  BuildContext context, {
  Task? existing,
  String? contactId,
}) {
  return showDialog<Task>(
    context: context,
    builder: (_) => _TaskForm(
      store: CrmScope.read(context),
      existing: existing,
      contactId: contactId,
    ),
  );
}

/// A margin typed as "25", "25%" or "22,5". Null when empty or not a number.
double? _parseMargin(String text) {
  final t = text.replaceAll('%', '').replaceAll(',', '.').trim();
  return t.isEmpty ? null : double.tryParse(t);
}

String? _validMargin(String? v) {
  if ((v ?? '').trim().isEmpty) return null;
  final m = _parseMargin(v!);
  if (m == null) return 'Enter a number';
  if (m < 0 || m >= 100) return 'Between 0 and 99';
  return null;
}

class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.formKey,
    required this.submitLabel,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final String submitLabel;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  children[i],
                ],
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
        FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
      ],
    );
  }
}

String? _required(String? value, String message) =>
    value == null || value.trim().isEmpty ? message : null;

// ------------------------------------------------------------------ contact

class _ContactForm extends StatefulWidget {
  const _ContactForm({
    required this.store,
    required this.kind,
    this.existing,
    this.initialName,
  });

  final CrmStore store;
  final ContactKind kind;
  final Contact? existing;
  final String? initialName;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.initialName,
  );
  late final _person = TextEditingController(
    text: widget.existing?.contactPerson,
  );
  late final _street = TextEditingController(text: widget.existing?.street);
  late final _zip = TextEditingController(text: widget.existing?.postalCode);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _website = TextEditingController(text: widget.existing?.website);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _depotMargin = TextEditingController(
    text: _marginText(widget.existing?.depotMargin),
  );
  late final _stockMargin = TextEditingController(
    text: _marginText(widget.existing?.stockMargin),
  );
  late var _status = widget.existing?.status ?? ContactStatus.lead;

  static String _marginText(double? m) =>
      m == null ? '' : formatMargin(m).replaceAll('%', '');
  late var _type = widget.existing?.type ?? ShopType.unknown;

  @override
  void dispose() {
    for (final c in [
      _name,
      _person,
      _street,
      _zip,
      _city,
      _email,
      _phone,
      _website,
      _notes,
      _depotMargin,
      _stockMargin,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final store = widget.store;
    final existing = widget.existing;
    final Contact result;
    if (existing == null) {
      result = store.addContact(
        name: _name.text.trim(),
        kind: widget.kind,
        type: _type,
        contactPerson: _person.text.trim(),
        street: _street.text.trim(),
        postalCode: _zip.text.trim(),
        city: _city.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        website: _website.text.trim(),
        status: _status,
        notes: _notes.text.trim(),
        depotMargin: _parseMargin(_depotMargin.text),
        stockMargin: _parseMargin(_stockMargin.text),
      );
    } else {
      final depot = _parseMargin(_depotMargin.text);
      final stock = _parseMargin(_stockMargin.text);
      result = existing.copyWith(
        depotMargin: () => depot,
        stockMargin: () => stock,
        name: _name.text.trim(),
        type: _type,
        contactPerson: _person.text.trim(),
        street: _street.text.trim(),
        postalCode: _zip.text.trim(),
        city: _city.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        website: _website.text.trim(),
        status: _status,
        notes: _notes.text.trim(),
      );
      store.updateContact(result);
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    if (widget.kind == ContactKind.person) return _buildPrivate(isNew);
    return _FormDialog(
      title: isNew ? 'New dealer' : 'Edit dealer',
      formKey: _formKey,
      submitLabel: isNew ? 'Add dealer' : 'Save',
      onSubmit: _submit,
      children: [
        AppFormField(
          controller: _name,
          label: 'Shop name',
          hint: 'E.g. Velo Muster GmbH',
          autofocus: isNew,
          validator: (v) => _required(v, 'Please enter a shop name'),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<ShopType>(
                initialValue: _type,
                isExpanded: true,
                decoration: inputDecoration('Sells'),
                items: [
                  for (final t in ShopType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        t == ShopType.unknown ? 'Not set' : t.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (t) => setState(() => _type = t ?? _type),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<ContactStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: inputDecoration('Status'),
                items: [
                  for (final s in ContactStatus.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (s) => setState(() => _status = s ?? _status),
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppFormField(
                controller: _depotMargin,
                label: 'Dépôt-vente margin %',
                hint: '${formatMargin(Contact.defaultDepotMargin)} if empty',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validMargin,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppFormField(
                controller: _stockMargin,
                label: 'Own stock margin %',
                hint: 'E.g. 30',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validMargin,
              ),
            ),
          ],
        ),
        AppFormField(
          controller: _person,
          label: 'Contact person',
          hint: 'First and last name',
        ),
        AppFormField(
          controller: _street,
          label: 'Street address',
          hint: 'E.g. Bahnhofstrasse 1',
        ),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: AppFormField(
                controller: _zip,
                label: 'Postal code',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppFormField(
                controller: _city,
                label: 'City',
                hint: 'E.g. Bern',
              ),
            ),
          ],
        ),
        AppFormField(
          controller: _phone,
          label: 'Phone',
          hint: '+41 31 123 45 67',
          keyboardType: TextInputType.phone,
        ),
        AppFormField(
          controller: _email,
          label: 'Email',
          hint: 'info@shop.ch',
          keyboardType: TextInputType.emailAddress,
          validator: _validEmail,
        ),
        AppFormField(
          controller: _website,
          label: 'Website',
          hint: 'shop.ch',
          keyboardType: TextInputType.url,
        ),
        AppFormField(
          controller: _notes,
          label: 'Notes',
          hint: 'Anything worth remembering?',
          maxLines: 3,
        ),
      ],
    );
  }

  /// A person buying for themselves: no shop type, contact person or website.
  Widget _buildPrivate(bool isNew) {
    return _FormDialog(
      title: isNew ? 'New private customer' : 'Edit private customer',
      formKey: _formKey,
      submitLabel: isNew ? 'Add customer' : 'Save',
      onSubmit: _submit,
      children: [
        AppFormField(
          controller: _name,
          label: 'Name',
          hint: 'First and last name',
          autofocus: isNew,
          validator: (v) => _required(v, 'Please enter a name'),
        ),
        AppFormField(
          controller: _phone,
          label: 'Phone',
          hint: '+41 79 123 45 67',
          keyboardType: TextInputType.phone,
        ),
        AppFormField(
          controller: _email,
          label: 'Email',
          hint: 'name@example.ch',
          keyboardType: TextInputType.emailAddress,
          validator: _validEmail,
        ),
        AppFormField(
          controller: _street,
          label: 'Street address',
          hint: 'E.g. Bahnhofstrasse 1',
        ),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: AppFormField(
                controller: _zip,
                label: 'Postal code',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppFormField(
                controller: _city,
                label: 'City',
                hint: 'E.g. Bern',
              ),
            ),
          ],
        ),
        DropdownButtonFormField<ContactStatus>(
          initialValue: _status,
          decoration: inputDecoration('Status'),
          items: [
            for (final s in ContactStatus.forPrivate)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged: (s) => setState(() => _status = s ?? _status),
        ),
        AppFormField(
          controller: _notes,
          label: 'Notes',
          hint: 'E.g. interested in a fatbike, test ride on Saturday',
          maxLines: 3,
        ),
      ],
    );
  }
}

String? _validEmail(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
      ? null
      : 'This email address is not valid';
}

// --------------------------------------------------------------------- deal

class _DealForm extends StatefulWidget {
  const _DealForm({required this.store, this.existing, this.contactId});

  final CrmStore store;
  final Deal? existing;
  final String? contactId;

  @override
  State<_DealForm> createState() => _DealFormState();
}

/// One editable order line in the deal form.
class _Line {
  _Line({
    this.productId,
    this.name = '',
    int quantity = 1,
    double? unitPrice,
    this.retail,
  }) : quantity = TextEditingController(text: '$quantity'),
       unitPrice = TextEditingController(
         text: unitPrice == null ? '' : formatAmount(unitPrice),
       );

  String? productId;
  String name;

  /// Retail price the unit price was worked out from. Null once the price
  /// was typed by hand (or on a saved deal): then it is left alone.
  double? retail;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  int get qty => int.tryParse(quantity.text.trim()) ?? 0;
  double get price => parseMoney(unitPrice.text) ?? 0;

  void dispose() {
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _DealFormState extends State<_DealForm> with _CustomerField {
  @override
  CrmStore get _store => widget.store;
  @override
  String? get _initialContactId =>
      widget.existing?.contactId ?? widget.contactId;

  final _formKey = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.existing == null ? '' : formatAmount(widget.existing!.value),
  );
  final _productSearch = TextEditingController();
  late var _stage = widget.existing?.stage ?? DealStage.nieuw;
  late final List<_Line> _lines = [
    for (final i in widget.existing?.items ?? const <DealItem>[])
      _Line(
        productId: i.productId,
        name: i.name,
        quantity: i.quantity,
        unitPrice: i.unitPrice,
      ),
  ];

  /// Bumped after each pick so the product search starts empty again.
  int _searchRound = 0;

  @override
  void dispose() {
    _value.dispose();
    _productSearch.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _linesTotal => _lines.fold(0, (sum, l) => sum + l.qty * l.price);

  /// The partner's own-stock margin for this deal (0 for private customers
  /// and new names).
  double get _margin => _customer?.effectiveStockMargin ?? 0;

  String? _pricedFor;

  /// How the product prices were worked out, for partners.
  String? get _priceNote {
    final c = _customer;
    if (c == null || c.isPrivate) return null;
    return c.stockMargin == null
        ? 'Retail prices: no own stock margin set for ${c.name}.'
        : 'Partner prices: retail minus ${formatMargin(c.effectiveStockMargin)} '
              'own stock margin.';
  }

  /// Works the prices out again for a new customer, except those typed in.
  @override
  void _customerChanged() {
    final id = _customer?.id;
    if (id == _pricedFor) return;
    _pricedFor = id;
    for (final l in _lines) {
      if (l.retail != null) {
        l.unitPrice.text = formatAmount(partnerPrice(l.retail!, _margin));
      }
    }
  }

  /// Adds a product, or one more of it when it is already on the deal.
  void _addProduct(String? id) {
    final product = widget.store.productById(id);
    if (product == null) return;
    setState(() {
      final existing = _lines.where((l) => l.productId == id).firstOrNull;
      if (existing != null) {
        existing.quantity.text = '${existing.qty + 1}';
      } else {
        _lines.add(
          _Line(
            productId: product.id,
            name: product.name,
            unitPrice: partnerPrice(product.price, _margin),
            retail: product.price,
          ),
        );
      }
      _productSearch.clear();
      _searchRound++;
    });
  }

  void _submit() {
    final formOk = _formKey.currentState!.validate();
    final customerOk = _checkCustomer(required: true);
    if (!formOk || !customerOk) return;
    final store = widget.store;
    _contactId = _saveCustomer();
    final existing = widget.existing;
    final items = [
      for (final l in _lines)
        DealItem(
          productId: l.productId,
          name: l.name,
          quantity: l.qty,
          unitPrice: l.price,
        ),
    ];
    final value = items.isEmpty ? (parseMoney(_value.text) ?? 0) : 0.0;
    // Deals are named after what is on them. A name typed in by hand on an
    // older deal is kept.
    final named =
        existing != null &&
        existing.title != dealTitleFor(existing.items, existing.createdAt);
    final title = named
        ? existing.title
        : dealTitleFor(items, existing?.createdAt ?? store.now());
    final Deal result;
    if (existing == null) {
      result = store.addDeal(
        contactId: _contactId!,
        title: title,
        value: value,
        stage: _stage,
        items: items,
      );
    } else {
      result = existing.copyWith(
        contactId: _contactId,
        title: title,
        value: value,
        stage: _stage,
        items: items,
      );
      store.updateDeal(result);
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final products = widget.store.products.where((p) => p.active).toList();
    return _AdaptiveFormDialog(
      title: isNew ? 'New deal' : 'Edit deal',
      formKey: _formKey,
      submitLabel: isNew ? 'Add deal' : 'Save',
      onSubmit: _submit,
      children: [
        // ---- who
        ..._customerField(saveWith: 'deal'),
        // ---- what
        if (products.isEmpty)
          const Text(
            'No products in the catalog yet. Enter the amount below.',
            style: TextStyle(color: muted, fontSize: 12),
          )
        else
          _ProductSearch(
            key: ValueKey(_searchRound),
            controller: _productSearch,
            products: products,
            onSelected: _addProduct,
          ),
        for (final line in _lines)
          _LineEditor(
            key: ObjectKey(line),
            item: line,
            onChanged: () => setState(() {}),
            onRemove: () => setState(() {
              _lines.remove(line);
              line.dispose();
            }),
          ),
        if (_lines.any((l) => l.retail != null) && _priceNote != null)
          Text(_priceNote!, style: const TextStyle(color: muted, fontSize: 12)),
        // ---- how much
        if (_lines.isEmpty)
          AppFormField(
            controller: _value,
            label: 'Amount ($currencyLabel)',
            hint: products.isEmpty ? '4,500' : 'Or add products above',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final parsed = parseMoney(v ?? '');
              if (parsed == null) return 'Add a product or enter an amount';
              if (parsed < 0) return 'The amount cannot be negative';
              return null;
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: sage,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      color: forest,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatMoney(_linesTotal),
                  style: const TextStyle(
                    color: forest,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        // ---- where it stands (a new deal starts as New)
        if (!isNew) const _SectionLabel('Stage'),
        if (!isNew)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in DealStage.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _stage == s,
                  showCheckmark: false,
                  avatar: Icon(Icons.circle, size: 10, color: stageColor(s)),
                  selectedColor: sage,
                  side: BorderSide(color: _stage == s ? forest : line),
                  labelStyle: TextStyle(
                    color: _stage == s ? forest : ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _stage = s),
                ),
            ],
          ),
      ],
    );
  }
}

/// Small heading that splits a form into steps.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A form in a dialog on wide screens and full screen on a phone, where a
/// long form is easier to fill in with the Save button always in reach.
class _AdaptiveFormDialog extends StatelessWidget {
  const _AdaptiveFormDialog({
    required this.title,
    required this.formKey,
    required this.submitLabel,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final String submitLabel;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return _FormDialog(
        title: title,
        formKey: formKey,
        submitLabel: submitLabel,
        onSubmit: onSubmit,
        children: children,
      );
    }
    return Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: const Border(bottom: BorderSide(color: line)),
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                children[i],
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: FilledButton(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(submitLabel),
            ),
          ),
        ),
      ),
    );
  }
}

/// Type-to-search field that adds the picked product to the deal.
class _ProductSearch extends StatelessWidget {
  const _ProductSearch({
    super.key,
    required this.controller,
    required this.products,
    required this.onSelected,
  });

  final TextEditingController controller;
  final List<Product> products;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DropdownMenu<String>(
        width: constraints.maxWidth,
        menuHeight: 320,
        controller: controller,
        enableFilter: true,
        requestFocusOnTap: true,
        label: const Text('Add product'),
        hintText: 'Type a name or article number',
        leadingIcon: const Icon(Icons.add_shopping_cart_rounded, size: 19),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: canvas,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: forest),
          ),
        ),
        onSelected: onSelected,
        dropdownMenuEntries: [
          for (final p in products)
            DropdownMenuEntry<String>(
              value: p.id,
              // The label is what the search matches: name and article number.
              label: p.sku.isEmpty ? p.name : '${p.name} · ${p.sku}',
              trailingIcon: Text(
                p.price > 0 ? formatMoney(p.price) : 'No price',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One product on the deal: name, quantity stepper, unit price and total.
class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final _Line item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  void _step(int delta) {
    final next = item.qty + delta;
    if (next < 1) return;
    item.quantity.text = '$next';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove product',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18, color: muted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.outlined(
                  tooltip: 'One less',
                  onPressed: item.qty > 1 ? () => _step(-1) : null,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 46,
                  child: TextFormField(
                    controller: item.quantity,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (_) => onChanged(),
                    validator: (v) =>
                        (int.tryParse(v?.trim() ?? '') ?? 0) < 1 ? '≥ 1' : null,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'One more',
                  onPressed: () => _step(1),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: item.unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: inputDecoration('Price each')
                        .copyWith(fillColor: Colors.white, isDense: true),
                    onChanged: (_) {
                      // A price typed by hand stays when the customer
                      // changes.
                      item.retail = null;
                      onChanged();
                    },
                    validator: (v) =>
                        parseMoney(v ?? '') == null ? 'Price?' : null,
                  ),
                ),
              ],
            ),
          ),
          if (item.qty > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${item.qty} × ${formatMoney(item.price)} = '
                  '${formatMoney(item.qty * item.price)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The customer field of the deal and task forms. Pick a dealer or private
/// customer from the list, or type a name: a name that is not in the CRM yet
/// is saved as a new private customer when the form is saved.
mixin _CustomerField<T extends StatefulWidget> on State<T> {
  CrmStore get _store;
  String? get _initialContactId;

  /// Whether the form may be saved without a customer ("Nobody").
  bool get _customerOptional => false;

  late String? _contactId = _initialContactId;

  /// What is typed in the customer field.
  final _who = TextEditingController();
  String? _whoError;

  @override
  void initState() {
    super.initState();
    _who.addListener(_whoChanged);
  }

  @override
  void dispose() {
    _who.dispose();
    super.dispose();
  }

  /// Refreshes the hint under the customer field. The field also changes its
  /// text while it is being built (after a pick), so wait for the frame then.
  void _whoChanged() {
    void refresh() {
      if (!mounted) return;
      setState(() => _whoError = null);
      _customerChanged();
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      refresh();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => refresh());
    }
  }

  /// Called after the customer in the field may have changed.
  void _customerChanged() {}

  String get _typed => _who.text.trim();

  /// The optional field's "Nobody" entry, picked or typed.
  bool _isNobody(String typed) =>
      _customerOptional &&
      typed.toLowerCase() == DealerPicker.nobody.toLowerCase();

  /// Contacts whose name (or full picker label) is exactly [typed].
  List<Contact> _named(String typed) {
    final key = typed.toLowerCase();
    return [
      for (final c in _store.allContacts)
        if (c.name.trim().toLowerCase() == key ||
            DealerPicker.labelFor(c).toLowerCase() == key)
          c,
    ];
  }

  /// The customer the field points to: the one picked from the list, or the
  /// only one whose name was typed in full. Null when nobody matches. A
  /// customer deleted while the form was open counts as nobody.
  Contact? get _customer {
    final picked = _store.contactById(_contactId);
    final typed = _typed;
    if (typed.isEmpty) return picked;
    if (_isNobody(typed)) return null;
    final named = _named(typed);
    if (picked != null && named.contains(picked)) return picked;
    return named.length == 1 ? named.single : null;
  }

  /// A typed name that is not in the CRM yet.
  bool get _typedIsNew =>
      _typed.isNotEmpty && !_isNobody(_typed) && _named(_typed).isEmpty;

  /// Shows why the field can't be saved; true when it can.
  bool _checkCustomer({required bool required}) {
    final typed = _typed;
    String? error;
    if (_customer == null && !_typedIsNew) {
      if (_named(typed).length > 1) {
        error = 'Several customers are called "$typed": pick one';
      } else if (required) {
        error = 'Choose a dealer or private customer';
      }
    }
    setState(() => _whoError = error);
    return error == null;
  }

  /// The customer to save the form with. A new name is saved in the CRM as a
  /// private customer first. Call after [_checkCustomer].
  String? _saveCustomer() {
    if (_typedIsNew) {
      return _store.addContact(name: _typed, kind: ContactKind.person).id;
    }
    return _customer?.id;
  }

  /// Creates a customer on the spot (prefilled with the typed name) and picks
  /// them.
  Future<void> _addCustomer(ContactKind kind) async {
    final customer = await showContactForm(
      context,
      kind: kind,
      initialName: _typedIsNew ? _typed : null,
    );
    if (customer == null || !mounted) return;
    setState(() {
      _contactId = customer.id;
      _whoError = null;
    });
    _who.text = DealerPicker.labelFor(customer);
  }

  /// The field, a hint when a new customer will be saved, and buttons to add
  /// one with all their details. [saveWith] names the record ("deal").
  List<Widget> _customerField({required String saveWith}) => [
    DealerPicker(
      store: _store,
      selectedId: _contactId,
      controller: _who,
      optional: _customerOptional,
      includePrivate: true,
      errorText: _whoError,
      onSelected: (id) => setState(() {
        _contactId = id;
        _whoError = null;
      }),
    ),
    if (_typedIsNew && _whoError == null)
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          '"$_typed" is not in the CRM yet. It will be saved as a new '
          'private customer with this $saveWith.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ),
    Wrap(
      children: [
        for (final (kind, icon, label) in [
          (
            ContactKind.person,
            Icons.person_add_alt_1_outlined,
            'New private customer',
          ),
          (ContactKind.dealer, Icons.add_business_outlined, 'New dealer'),
        ])
          TextButton.icon(
            onPressed: () => _addCustomer(kind),
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: forest,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    ),
  ];
}

/// Searchable dealer field — a plain dropdown is unusable with 200+ dealers.
/// With [includePrivate], private customers can be picked too.
class DealerPicker extends StatelessWidget {
  const DealerPicker({
    super.key,
    required this.store,
    required this.selectedId,
    required this.onSelected,
    this.optional = false,
    this.includePrivate = false,
    this.errorText,
    this.controller,
  });

  final CrmStore store;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool optional;
  final bool includePrivate;
  final String? errorText;

  /// Holds the typed text, for forms that use what was typed.
  final TextEditingController? controller;

  /// The optional field's entry for no customer.
  static const nobody = 'Nobody';

  /// How [c] is shown in the list and in the field once picked.
  static String labelFor(Contact c) => [
    c.name,
    if (c.city.isNotEmpty) c.city,
    if (c.isPrivate) 'private',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final dealers = [...(includePrivate ? store.allContacts : store.contacts)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final noun = includePrivate ? 'Customer' : 'Dealer';
    return LayoutBuilder(
      builder: (context, constraints) => DropdownMenu<String?>(
        key: ValueKey(selectedId),
        width: constraints.maxWidth,
        menuHeight: 320,
        initialSelection: selectedId,
        controller: controller,
        enableFilter: true,
        requestFocusOnTap: true,
        label: Text(optional ? '$noun (optional)' : noun),
        hintText: 'Type to search',
        errorText: errorText,
        leadingIcon: Icon(
          includePrivate
              ? Icons.people_outline_rounded
              : Icons.storefront_outlined,
          size: 19,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: canvas,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: forest),
          ),
        ),
        onSelected: onSelected,
        dropdownMenuEntries: [
          if (optional)
            DropdownMenuEntry<String?>(
              value: null,
              label: includePrivate ? nobody : 'No dealer',
            ),
          for (final c in dealers)
            DropdownMenuEntry<String?>(
              value: c.id,
              label: labelFor(c),
              leadingIcon: includePrivate
                  ? Icon(
                      c.isPrivate
                          ? Icons.person_outline_rounded
                          : Icons.storefront_outlined,
                      size: 18,
                      color: muted,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- task

class _TaskForm extends StatefulWidget {
  const _TaskForm({required this.store, this.existing, this.contactId});

  final CrmStore store;
  final Task? existing;
  final String? contactId;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> with _CustomerField {
  @override
  CrmStore get _store => widget.store;
  @override
  String? get _initialContactId =>
      widget.existing?.contactId ?? widget.contactId;
  @override
  bool get _customerOptional => true;

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late DateTime _due = widget.existing?.due ?? _defaultDue();

  DateTime _defaultDue() {
    final now = widget.store.now();
    // Next full hour, or 9:00 tomorrow when it's late.
    final next = DateTime(now.year, now.month, now.day, now.hour + 1);
    if (next.hour >= 18 || next.day != now.day) {
      final tomorrow = dateOnly(now).add(const Duration(days: 1));
      return tomorrow.add(const Duration(hours: 9));
    }
    return next;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(
      () => _due = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _due.hour,
        _due.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
    );
    if (picked == null) return;
    setState(
      () => _due = DateTime(
        _due.year,
        _due.month,
        _due.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  void _submit() {
    final formOk = _formKey.currentState!.validate();
    final customerOk = _checkCustomer(required: false);
    if (!formOk || !customerOk) return;
    final store = widget.store;
    _contactId = _saveCustomer();
    final existing = widget.existing;
    final Task result;
    if (existing == null) {
      result = store.addTask(
        title: _title.text.trim(),
        due: _due,
        contactId: _contactId,
      );
    } else {
      result = existing.copyWith(
        title: _title.text.trim(),
        due: _due,
        contactId: () => _contactId,
      );
      store.updateTask(result);
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final now = widget.store.now();
    return _FormDialog(
      title: isNew ? 'New task' : 'Edit task',
      formKey: _formKey,
      submitLabel: isNew ? 'Add task' : 'Save',
      onSubmit: _submit,
      children: [
        AppFormField(
          controller: _title,
          label: 'Task',
          hint: 'E.g. follow up on quote',
          autofocus: isNew,
          validator: (v) => _required(v, 'Please enter a task'),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(formatDay(_due, now)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(formatTime(_due)),
              ),
            ),
          ],
        ),
        ..._customerField(saveWith: 'task'),
      ],
    );
  }
}
