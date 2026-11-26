import 'package:flutter/material.dart';

import '../crm_store.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/data_tools.dart';

void openProducts(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ProductsPage()));
}

/// The product catalog used for order lines on deals. Online it is the
/// catalog shared with the Offers and Inventory apps, shown read-only.
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final shared = store.productsReadOnly;
    // The shared catalog arrives in its own order (Fatbikes first).
    final products = shared
        ? store.products
        : ([...store.products]..sort((a, b) {
            if (a.active != b.active) return a.active ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }));
    final sales = {for (final s in store.wonProductSales()) s.name: s};
    final rows = <Widget>[];
    String? group;
    for (final p in products) {
      if (shared && p.category != group) {
        group = p.category;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: rows.isEmpty ? 10 : 18, bottom: 4),
            child: Text(
              group.isEmpty ? 'Other' : group,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        );
      }
      rows.add(
        _ProductRow(
          product: p,
          unitsSold: sales[p.name]?.units ?? 0,
          editable: !shared,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: const Border(bottom: BorderSide(color: line)),
        title: const Text(
          'Products',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pad = constraints.maxWidth < 680 ? 18.0 : 36.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 24, pad, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageHeader(
                      title: 'Your products',
                      subtitle: shared
                          ? 'The fatbikes from the catalog of the Offers and '
                                'Inventory apps, with sales prices incl. VAT. '
                                'Change products and prices there.'
                          : 'Models and dealer prices for order lines.',
                      action: shared
                          ? null
                          : PrimaryButton(
                              label: 'New product',
                              onPressed: () => showProductForm(context),
                            ),
                    ),
                    const SizedBox(height: 24),
                    Panel(
                      padding: const EdgeInsets.fromLTRB(18, 8, 6, 8),
                      child: products.isEmpty
                          ? EmptyState(
                              icon: Icons.pedal_bike_rounded,
                              message: shared
                                  ? 'No fatbikes in the shared catalog yet. '
                                        'Open the Offers app once to fill it.'
                                  : 'No products yet. Add your models to use '
                                        'them as order lines on deals.',
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: rows,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.unitsSold,
    required this.editable,
  });

  final Product product;
  final int unitsSold;

  /// False for the shared catalog, which is edited in the Offers app.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.read(context);
    final details = [
      if (product.sku.isNotEmpty) product.sku,
      '$unitsSold sold',
      if (!product.active) 'inactive',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: editable
          ? () => showProductForm(context, existing: product)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: product.active ? sage : canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.pedal_bike_rounded,
                size: 19,
                color: product.active ? forest : muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: product.active ? ink : muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              product.price > 0 ? formatMoney(product.price) : 'No price',
              style: TextStyle(
                color: product.price > 0 ? ink : muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!editable) const SizedBox(width: 12),
            if (editable)
              PopupMenuButton<String>(
                tooltip: 'Product actions',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: muted,
                ),
                onSelected: (action) async {
                  switch (action) {
                    case 'edit':
                      showProductForm(context, existing: product);
                    case 'toggle':
                      store.updateProduct(
                        product.copyWith(active: !product.active),
                      );
                    case 'delete':
                      final ok = await confirmDelete(
                        context,
                        title: 'Delete product?',
                        message:
                            '${product.name} will be removed from the catalog. '
                            'Existing deals keep their order lines.',
                      );
                      if (ok) store.deleteProduct(product.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      product.active ? 'Mark as inactive' : 'Mark as active',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showProductForm(BuildContext context, {Product? existing}) {
  final store = CrmScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _ProductForm(store: store, existing: existing),
  );
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({required this.store, this.existing});

  final CrmStore store;
  final Product? existing;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _sku = TextEditingController(text: widget.existing?.sku);
  late final _price = TextEditingController(
    text: widget.existing == null ? '' : formatAmount(widget.existing!.price),
  );

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = parseMoney(_price.text) ?? 0;
    final existing = widget.existing;
    if (existing == null) {
      widget.store.addProduct(
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        price: price,
      );
    } else {
      widget.store.updateProduct(
        existing.copyWith(
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          price: price,
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(
        isNew ? 'New product' : 'Edit product',
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                controller: _name,
                label: 'Name',
                hint: 'E.g. E-Fatbike 26″',
                autofocus: isNew,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter a name'
                    : null,
              ),
              const SizedBox(height: 14),
              AppFormField(
                controller: _sku,
                label: 'Article number (optional)',
              ),
              const SizedBox(height: 14),
              AppFormField(
                controller: _price,
                label: 'Dealer price ($currencyLabel)',
                hint: '2,500',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final parsed = parseMoney(v ?? '');
                  if (parsed == null) return 'Please enter a price';
                  if (parsed < 0) return 'The price cannot be negative';
                  return null;
                },
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
          onPressed: _submit,
          child: Text(isNew ? 'Add product' : 'Save'),
        ),
      ],
    );
  }
}
