import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_import.dart';
import 'format.dart';
import 'models.dart';

/// Where the CRM data lives. Swappable so tests can run in memory.
abstract class CrmStorage {
  Future<String?> load();
  Future<void> save(String data);

  /// Whether to fill an empty store with demo data (local storage only).
  bool get seedDemoWhenEmpty => true;

  /// Full state (backup JSON) whenever it changes elsewhere, e.g. another
  /// device editing the same cloud database. Null for local storage.
  Stream<String>? get changes => null;

  /// True when products come from the catalog shared with the Offers and
  /// Inventory apps: the CRM then only reads them and never saves them.
  bool get sharedCatalog => false;
}

class SharedPrefsStorage extends CrmStorage {
  static const _key = 'molenstraat_crm_v1';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String data) async =>
      (await SharedPreferences.getInstance()).setString(_key, data);
}

class MemoryStorage extends CrmStorage {
  MemoryStorage([this.data]);
  String? data;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String data) async => this.data = data;
}

/// Single source of truth for contacts, deals, tasks and the activity feed.
class CrmStore extends ChangeNotifier {
  CrmStore({required this.storage, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final CrmStorage storage;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  List<Contact> _contacts = [];
  List<Deal> _deals = [];
  List<Task> _tasks = [];
  List<Activity> _activities = [];
  List<Product> _products = [];
  List<ConsignedBike> _bikes = [];
  int _idCounter = 0;

  /// Signed-in account when using the online database (null when local).
  String? accountEmail;

  /// Signs out of the online database; null when running locally.
  Future<void> Function()? onSignOut;

  /// Your name, shown in the greeting and sidebar.
  String userName = defaultUserName;

  /// 'CHF' or 'EUR'.
  String currency = 'CHF';

  static const defaultUserName = 'Jonas Mühle';

  String get firstName => userName.trim().split(' ').first;

  /// Dealers, newest first. Private customers are kept out so dealer lists,
  /// stats, imports and exports stay about shops.
  List<Contact> get contacts =>
      List.unmodifiable(_contacts.where((c) => !c.isPrivate));

  /// Private customers, newest first.
  List<Contact> get privateCustomers =>
      List.unmodifiable(_contacts.where((c) => c.isPrivate));

  /// Dealers and private customers, newest first.
  List<Contact> get allContacts => List.unmodifiable(_contacts);
  List<Deal> get deals => List.unmodifiable(_deals);
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<Activity> get activities => List.unmodifiable(_activities);

  /// Products for deals. From the shared catalog only the fatbikes: spare
  /// parts and accessories are sold through the Offers app, not as deals.
  List<Product> get products => List.unmodifiable(
    productsReadOnly ? _products.where((p) => p.isFatbike) : _products,
  );
  List<ConsignedBike> get bikes => List.unmodifiable(_bikes);

  Future<void> load() async {
    final raw = await storage.load();
    if (raw == null) {
      if (storage.seedDemoWhenEmpty) {
        _seedDemo();
        await _persist();
      }
    } else {
      _applyJson(jsonDecode(raw) as Map<String, Object?>);
    }
    moneyCurrency = currency;
    _remote?.cancel();
    _remote = storage.changes?.listen(_applyRemote);
    notifyListeners();
  }

  StreamSubscription<String>? _remote;

  /// Applies a state pushed by the storage (someone else's edit).
  void _applyRemote(String raw) {
    final json = jsonDecode(raw) as Map<String, Object?>;
    // Our own writes echo back; skip when nothing actually differs.
    if (jsonEncode(json) == jsonEncode(_toJson())) return;
    _applyJson(json);
    moneyCurrency = currency;
    notifyListeners();
  }

  bool get isEmpty =>
      _contacts.isEmpty &&
      _deals.isEmpty &&
      _tasks.isEmpty &&
      _products.isEmpty &&
      _bikes.isEmpty;

  @override
  void dispose() {
    _remote?.cancel();
    super.dispose();
  }

  void _applyJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) => [
      for (final e in (json[key] as List?) ?? const [])
        (e as Map).cast<String, Object?>(),
    ];
    _contacts = list('contacts').map(Contact.fromJson).toList();
    _deals = list('deals').map(Deal.fromJson).toList();
    _tasks = list('tasks').map(Task.fromJson).toList();
    _activities = list('activities').map(Activity.fromJson).toList();
    _products = list('products').map(Product.fromJson).toList();
    _bikes = list('bikes').map(ConsignedBike.fromJson).toList();
    final settings = (json['settings'] as Map?)?.cast<String, Object?>();
    userName = settings?['userName'] as String? ?? defaultUserName;
    final cur = settings?['currency'] as String?;
    currency = supportedCurrencies.contains(cur) ? cur! : 'CHF';
  }

  Map<String, Object?> _toJson() => {
    'app': 'molenstraat-crm',
    'version': 2,
    'settings': {'userName': userName, 'currency': currency},
    'contacts': [for (final c in _contacts) c.toJson()],
    'deals': [for (final d in _deals) d.toJson()],
    'tasks': [for (final t in _tasks) t.toJson()],
    'activities': [for (final a in _activities) a.toJson()],
    'products': [for (final p in _products) p.toJson()],
    'bikes': [for (final b in _bikes) b.toJson()],
  };

  Future<void> _persist() => storage.save(jsonEncode(_toJson()));

  void _changed() {
    notifyListeners();
    _persist();
  }

  String _newId() => '${now().microsecondsSinceEpoch}-${_idCounter++}';

  void _log(String? contactId, String message) {
    _activities.insert(
      0,
      Activity(id: _newId(), contactId: contactId, message: message, at: now()),
    );
    // Keep the automatic feed short, but never drop calls/visits/notes the
    // user logged.
    var system = 0;
    _activities.removeWhere(
      (a) => a.kind == ActivityKind.system && ++system > 200,
    );
  }

  // ---------------------------------------------------------------- settings

  void updateSettings({String? userName, String? currency}) {
    if (userName != null && userName.trim().isNotEmpty) {
      this.userName = userName.trim();
    }
    if (currency != null && supportedCurrencies.contains(currency)) {
      this.currency = currency;
      moneyCurrency = currency;
    }
    _changed();
  }

  // ------------------------------------------------------------ backup/export

  /// Full backup of all data as pretty-printed JSON.
  String exportBackup() =>
      const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Replaces all data with a backup made by [exportBackup].
  /// Throws [FormatException] when the file isn't a valid backup.
  void restoreBackup(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('This file is not a backup (invalid JSON).');
    }
    if (json is! Map || json['app'] != 'molenstraat-crm') {
      throw const FormatException('This file is not a Molenstraat CRM backup.');
    }
    // Parse fully before replacing anything, so a broken file changes nothing.
    final previous = _toJson();
    final keptProducts = _products;
    try {
      _applyJson(json.cast<String, Object?>());
    } catch (_) {
      _applyJson(previous);
      throw const FormatException('The backup file is damaged.');
    }
    // The shared catalog is not part of what a backup restores.
    if (productsReadOnly) _products = keptProducts;
    moneyCurrency = currency;
    _changed();
  }

  /// Dealers as CSV, in a format [contactsFromCsv] can read back.
  String exportDealersCsv() {
    String cell(String v) =>
        RegExp(r'[",\n\r]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    final rows = [
      [
        'Company name',
        'Type',
        'Contact person',
        'Street Address',
        'Postal Code',
        'City',
        'Phone Number',
        'Email',
        'Website URL',
        'Lifecycle Stage',
        'Last contact',
        'Notes',
        'Create Date',
      ],
      for (final c in contacts)
        [
          c.name,
          c.type == ShopType.unknown ? '' : c.type.label,
          c.contactPerson,
          c.street,
          c.postalCode,
          c.city,
          c.phone,
          c.email,
          c.website,
          c.status.label,
          lastContactAt(c.id)?.toIso8601String() ?? '',
          c.notes,
          c.createdAt.toIso8601String(),
        ],
    ];
    return rows.map((r) => r.map(cell).join(',')).join('\n');
  }

  // ---------------------------------------------------------------- contacts

  Contact? contactById(String? id) {
    if (id == null) return null;
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  Contact addContact({
    required String name,
    ContactKind kind = ContactKind.dealer,
    ShopType type = ShopType.unknown,
    String contactPerson = '',
    String street = '',
    String postalCode = '',
    String city = '',
    String email = '',
    String phone = '',
    String website = '',
    ContactStatus status = ContactStatus.lead,
    String notes = '',
    double? depotMargin,
    double? stockMargin,
  }) {
    final contact = Contact(
      id: _newId(),
      kind: kind,
      name: name,
      type: type,
      contactPerson: contactPerson,
      street: street,
      postalCode: postalCode,
      city: city,
      email: email,
      phone: phone,
      website: website,
      status: status,
      createdAt: now(),
      notes: notes,
      depotMargin: depotMargin,
      stockMargin: stockMargin,
    );
    _contacts.insert(0, contact);
    _log(
      contact.id,
      contact.isPrivate
          ? 'was added as a private customer'
          : 'was added as a dealer',
    );
    _changed();
    return contact;
  }

  /// Index of the existing dealer an imported row refers to. Private
  /// customers never match: imports are about shops.
  ///
  /// Matches on shop name (case-insensitive). Email is only used for entries
  /// without a real name (where the email stands in as the name), because
  /// branches of a chain often share one email or website.
  int _matchIndex(List<Contact> list, ContactDraft d) {
    final name = d.name.trim().toLowerCase();
    final byName = list.indexWhere(
      (c) => !c.isPrivate && c.name.trim().toLowerCase() == name,
    );
    if (byName >= 0) return byName;
    final email = d.email.trim().toLowerCase();
    if (email.isEmpty) return -1;
    final draftIsPlaceholder = name == email;
    return list.indexWhere((c) {
      if (c.isPrivate) return false;
      final cEmail = c.email.trim().toLowerCase();
      final cIsPlaceholder = c.name.trim().toLowerCase() == cEmail;
      return cEmail == email && (draftIsPlaceholder || cIsPlaceholder);
    });
  }

  /// Preview of what [importContacts] would do, without changing anything.
  ({int added, int updated}) previewImport(List<ContactDraft> drafts) {
    final simulated = List.of(_contacts);
    var added = 0, updated = 0;
    for (final d in drafts) {
      if (_matchIndex(simulated, d) >= 0) {
        updated++;
      } else {
        added++;
        simulated.add(_fromDraft(d));
      }
    }
    return (added: added, updated: updated);
  }

  Contact _fromDraft(ContactDraft d) => Contact(
    id: _newId(),
    name: d.name,
    type: d.type,
    contactPerson: d.contactPerson,
    street: d.street,
    postalCode: d.postalCode,
    city: d.city,
    email: d.email,
    phone: d.phone,
    website: d.website,
    notes: d.notes,
    status: d.status,
    createdAt: d.createdAt?.toLocal() ?? now(),
  );

  /// Adds imported dealers. Dealers that already exist (same email or shop
  /// name) are not duplicated; only their empty fields are filled in, so
  /// edits made in the app are never overwritten.
  ({int added, int updated}) importContacts(
    List<ContactDraft> drafts, {
    String source = 'a file',
  }) {
    var added = 0, updated = 0;
    String? fill(String current, String incoming) =>
        current.trim().isEmpty && incoming.trim().isNotEmpty ? incoming : null;
    for (final d in drafts) {
      final index = _matchIndex(_contacts, d);
      if (index >= 0) {
        final c = _contacts[index];
        _contacts[index] = c.copyWith(
          // Replace a placeholder name (the email) with a real one.
          name: c.name == c.email && d.name != d.email ? d.name : null,
          type: c.type == ShopType.unknown && d.type != ShopType.unknown
              ? d.type
              : null,
          contactPerson: fill(c.contactPerson, d.contactPerson),
          street: fill(c.street, d.street),
          postalCode: fill(c.postalCode, d.postalCode),
          city: fill(c.city, d.city),
          notes: fill(c.notes, d.notes),
          email: fill(c.email, d.email),
          phone: fill(c.phone, d.phone),
          website: fill(c.website, d.website),
        );
        updated++;
      } else {
        _contacts.add(_fromDraft(d));
        added++;
      }
    }
    // Keep the list newest-first.
    _contacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (added + updated > 0) {
      _log(
        null,
        added > 0
            ? 'imported $added new dealers from $source'
            : 'updated $updated dealers from $source',
      );
      _changed();
    }
    return (added: added, updated: updated);
  }

  void updateContact(Contact updated) {
    final index = _contacts.indexWhere((c) => c.id == updated.id);
    if (index < 0) return;
    final old = _contacts[index];
    _contacts[index] = updated;
    if (old.status != updated.status) {
      _log(updated.id, 'is now a ${updated.status.label.toLowerCase()}');
    }
    _changed();
  }

  /// Removes the contact together with its deals, tasks and activity.
  void deleteContact(String id) {
    if (bikesAt(id).isNotEmpty) {
      throw StateError('Dealer still holds consignment bikes.');
    }
    _bikes.removeWhere((b) => b.contactId == id);
    _contacts.removeWhere((c) => c.id == id);
    _deals.removeWhere((d) => d.contactId == id);
    _tasks.removeWhere((t) => t.contactId == id);
    _activities.removeWhere((a) => a.contactId == id);
    _changed();
  }

  List<Deal> dealsFor(String contactId) =>
      _deals.where((d) => d.contactId == contactId).toList();

  List<Task> tasksFor(String contactId) =>
      _tasks.where((t) => t.contactId == contactId).toList()
        ..sort((a, b) => a.due.compareTo(b.due));

  List<Activity> activitiesFor(String contactId) =>
      _activities.where((a) => a.contactId == contactId).toList();

  // ------------------------------------------------------------------- deals

  Deal addDeal({
    required String contactId,
    required String title,
    required double value,
    DealStage stage = DealStage.nieuw,
    List<DealItem> items = const [],
  }) {
    final deal = Deal(
      id: _newId(),
      contactId: contactId,
      title: title,
      value: value,
      items: items,
      stage: stage,
      createdAt: now(),
      closedAt: stage.isOpen ? null : now(),
    );
    _deals.insert(0, deal);
    _log(contactId, 'has a new deal: $title');
    _promoteContact(contactId, stage);
    _changed();
    return deal;
  }

  void updateDeal(Deal updated) {
    final index = _deals.indexWhere((d) => d.id == updated.id);
    if (index < 0) return;
    final old = _deals[index];
    var deal = updated;
    if (old.stage != updated.stage) {
      deal = updated.copyWith(
        closedAt: () => updated.stage.isOpen ? null : now(),
      );
      _log(deal.contactId, switch (deal.stage) {
        DealStage.gewonnen => 'awarded "${deal.title}" 🎉',
        DealStage.verloren => 'passed on "${deal.title}"',
        _ => '"${deal.title}" moved to ${deal.stage.label.toLowerCase()}',
      });
      _promoteContact(deal.contactId, deal.stage);
    }
    _deals[index] = deal;
    _changed();
  }

  void moveDeal(String dealId, DealStage stage) {
    final deal = _deals.where((d) => d.id == dealId).firstOrNull;
    if (deal != null) updateDeal(deal.copyWith(stage: stage));
  }

  void deleteDeal(String id) {
    _deals.removeWhere((d) => d.id == id);
    _changed();
  }

  /// A won deal turns a lead into a customer. Partners stay partners.
  void _promoteContact(String contactId, DealStage stage) {
    final index = _contacts.indexWhere((c) => c.id == contactId);
    if (index < 0) return;
    final contact = _contacts[index];
    if (stage == DealStage.gewonnen && contact.status == ContactStatus.lead) {
      _contacts[index] = contact.copyWith(status: ContactStatus.klant);
    }
  }

  // ------------------------------------------------------------ interactions

  /// Logs a call, visit, email or note with a dealer.
  Activity logInteraction({
    required String contactId,
    required ActivityKind kind,
    required String note,
    DateTime? at,
  }) {
    final activity = Activity(
      id: _newId(),
      contactId: contactId,
      kind: kind,
      message: note,
      at: at ?? now(),
    );
    _activities.add(activity);
    _activities.sort((a, b) => b.at.compareTo(a.at));
    _changed();
    return activity;
  }

  void deleteActivity(String id) {
    _activities.removeWhere((a) => a.id == id);
    _changed();
  }

  /// Most recent logged call/visit/email/note with this dealer.
  DateTime? lastContactAt(String contactId) {
    DateTime? latest;
    for (final a in _activities) {
      if (a.contactId == contactId &&
          a.isInteraction &&
          (latest == null || a.at.isAfter(latest))) {
        latest = a.at;
      }
    }
    return latest;
  }

  // ---------------------------------------------------------------- products

  /// Products are the shared Offers/Inventory catalog and can't be changed
  /// here (see [CrmStorage.sharedCatalog]).
  bool get productsReadOnly => storage.sharedCatalog;

  Product? productById(String? id) {
    if (id == null) return null;
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Product addProduct({
    required String name,
    required double price,
    String sku = '',
  }) {
    final product = Product(id: _newId(), name: name, price: price, sku: sku);
    _products.add(product);
    _changed();
    return product;
  }

  void updateProduct(Product updated) {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index < 0) return;
    _products[index] = updated;
    _changed();
  }

  /// Deletes a product. Existing deals keep their copied order lines.
  void deleteProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    _changed();
  }

  /// Units and revenue per product name across won deals, best first.
  List<({String name, int units, double revenue})> wonProductSales() {
    final units = <String, int>{};
    final revenue = <String, double>{};
    for (final d in _deals.where((d) => d.stage == DealStage.gewonnen)) {
      for (final i in d.items) {
        units.update(i.name, (u) => u + i.quantity, ifAbsent: () => i.quantity);
        revenue.update(i.name, (r) => r + i.total, ifAbsent: () => i.total);
      }
    }
    return [
      for (final name in units.keys)
        (name: name, units: units[name]!, revenue: revenue[name]!),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  }

  // ------------------------------------------------------------- consignment

  ConsignedBike? bikeById(String id) {
    for (final b in _bikes) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Finds a bike by frame number, ignoring case, spaces and dashes.
  ConsignedBike? bikeByFrame(String frame, {String? exceptId}) {
    final key = ConsignedBike.normalizeFrame(frame);
    if (key.isEmpty) return null;
    for (final b in _bikes) {
      if (b.id != exceptId &&
          ConsignedBike.normalizeFrame(b.frameNumber) == key) {
        return b;
      }
    }
    return null;
  }

  /// Bikes currently at this dealer.
  List<ConsignedBike> bikesAt(String contactId) =>
      _bikes.where((b) => b.contactId == contactId && b.isAtDealer).toList()
        ..sort((a, b) => a.placedAt.compareTo(b.placedAt));

  /// All bikes (any status) last held by this dealer, newest first.
  List<ConsignedBike> bikesFor(String contactId) =>
      _bikes.where((b) => b.contactId == contactId).toList()
        ..sort((a, b) => b.placedAt.compareTo(a.placedAt));

  List<ConsignedBike> get bikesAtDealers =>
      _bikes.where((b) => b.isAtDealer).toList();

  double get consignmentValueAtDealers =>
      bikesAtDealers.fold(0, (sum, b) => sum + b.price);

  List<ConsignedBike> get bikesAwaitingPayment =>
      _bikes.where((b) => b.awaitingPayment).toList();

  double get consignmentAmountOwed =>
      bikesAwaitingPayment.fold(0, (sum, b) => sum + b.price);

  String _dealerName(String id) => contactById(id)?.name ?? 'unknown dealer';

  ConsignedBike _withEvent(ConsignedBike b, String text, DateTime at) =>
      b.copyWith(
        history: [
          ...b.history,
          BikeEvent(at: at, text: text),
        ],
      );

  void _replaceBike(ConsignedBike updated) {
    final i = _bikes.indexWhere((b) => b.id == updated.id);
    if (i >= 0) _bikes[i] = updated;
  }

  /// Places one bike per frame number at a dealer. Frame numbers must be new;
  /// duplicates throw an [ArgumentError] and nothing is added.
  List<ConsignedBike> placeBikes({
    required String contactId,
    required List<String> frameNumbers,
    required String model,
    String? productId,
    double price = 0,
    DateTime? placedAt,
    String notes = '',
  }) => placeBikeBatch(
    contactId: contactId,
    bikes: [
      for (final f in frameNumbers)
        (frameNumber: f, model: model, productId: productId, price: price),
    ],
    placedAt: placedAt,
    notes: notes,
  );

  /// Places several bikes at a dealer at once, each with its own model and
  /// price. Throws when a frame number is entered twice or already exists.
  List<ConsignedBike> placeBikeBatch({
    required String contactId,
    required List<NewBike> bikes,
    DateTime? placedAt,
    String notes = '',
  }) {
    final todo = [
      for (final b in bikes)
        if (b.frameNumber.trim().isNotEmpty) b,
    ];
    final seen = <String>{};
    for (final b in todo) {
      final f = b.frameNumber.trim();
      if (!seen.add(ConsignedBike.normalizeFrame(f)) ||
          bikeByFrame(f) != null) {
        throw ArgumentError('Frame number $f already exists.');
      }
    }
    final at = placedAt ?? now();
    final placed = [
      for (final b in todo)
        ConsignedBike(
          id: _newId(),
          frameNumber: b.frameNumber.trim(),
          model: b.model,
          productId: b.productId,
          contactId: contactId,
          placedAt: at,
          price: b.price,
          notes: notes,
          history: [
            BikeEvent(at: at, text: 'Placed at ${_dealerName(contactId)}'),
          ],
        ),
    ];
    _bikes.addAll(placed);
    if (placed.isNotEmpty) {
      _log(contactId, _placedMessage(placed));
      _changed();
    }
    return placed;
  }

  /// "received Mooi (F-1)", "received 3 × Mooi" or
  /// "received 3 bikes (2 × Mooi, 1 × Storm)" … "on consignment".
  static String _placedMessage(List<ConsignedBike> placed) {
    final perModel = <String, int>{};
    for (final b in placed) {
      perModel[b.model] = (perModel[b.model] ?? 0) + 1;
    }
    final String what;
    if (placed.length == 1) {
      what = '${placed.single.model} (${placed.single.frameNumber})';
    } else if (perModel.length == 1) {
      what = '${placed.length} × ${placed.first.model}';
    } else {
      final parts = [for (final e in perModel.entries) '${e.value} × ${e.key}'];
      what = '${placed.length} bikes (${parts.join(', ')})';
    }
    return 'received $what on consignment';
  }

  /// The catalog product with this model name, if there is one.
  Product? productForModel(String model) {
    final name = model.trim().toLowerCase();
    for (final p in _products) {
      if (p.name.trim().toLowerCase() == name) return p;
    }
    return null;
  }

  /// Edits frame number, model, price or notes (not the status).
  void updateBike(ConsignedBike updated) {
    final clash = bikeByFrame(updated.frameNumber, exceptId: updated.id);
    if (clash != null) {
      throw ArgumentError(
        'Frame number ${updated.frameNumber} already exists.',
      );
    }
    _replaceBike(updated);
    _changed();
  }

  void markBikeSold(String id, {DateTime? at, double? salePrice}) {
    final b = bikeById(id);
    if (b == null) return;
    final when = at ?? now();
    _replaceBike(
      _withEvent(
        b.copyWith(
          status: ConsignmentStatus.sold,
          soldAt: () => when,
          salePrice: () => salePrice,
          paid: false,
          returnedAt: () => null,
        ),
        'Sold by ${_dealerName(b.contactId)}',
        when,
      ),
    );
    _log(b.contactId, 'sold ${b.model} (${b.frameNumber})');
    _changed();
  }

  void setBikePaid(String id, bool paid) {
    final b = bikeById(id);
    if (b == null || b.status != ConsignmentStatus.sold) return;
    _replaceBike(
      _withEvent(
        b.copyWith(paid: paid),
        paid ? 'Payment received' : 'Marked as not paid',
        now(),
      ),
    );
    _changed();
  }

  void markBikeReturned(String id, {DateTime? at}) {
    final b = bikeById(id);
    if (b == null) return;
    final when = at ?? now();
    _replaceBike(
      _withEvent(
        b.copyWith(
          status: ConsignmentStatus.returned,
          returnedAt: () => when,
          soldAt: () => null,
          salePrice: () => null,
          paid: false,
        ),
        'Returned by ${_dealerName(b.contactId)}',
        when,
      ),
    );
    _log(b.contactId, 'returned ${b.model} (${b.frameNumber})');
    _changed();
  }

  /// Moves a bike to another dealer (or places a returned bike again).
  /// Moves (or places again) a bike at [toContactId], with [price] as its
  /// new price when given.
  void moveBike(String id, String toContactId, {DateTime? at, double? price}) {
    final b = bikeById(id);
    if (b == null) return;
    final when = at ?? now();
    final from = b.contactId;
    final moved = b.isAtDealer
        ? 'Moved from ${_dealerName(from)} to ${_dealerName(toContactId)}'
        : 'Placed at ${_dealerName(toContactId)}';
    final text = price == null || price == b.price
        ? moved
        : '$moved, price ${formatMoney(price)}';
    _replaceBike(
      _withEvent(
        b.copyWith(
          contactId: toContactId,
          placedAt: when,
          price: price,
          status: ConsignmentStatus.atDealer,
          soldAt: () => null,
          salePrice: () => null,
          paid: false,
          returnedAt: () => null,
        ),
        text,
        when,
      ),
    );
    _log(toContactId, 'received ${b.model} (${b.frameNumber}) on consignment');
    _changed();
  }

  void deleteBike(String id) {
    _bikes.removeWhere((b) => b.id == id);
    _changed();
  }

  /// Consignment bikes as CSV (e.g. for a stock check with a dealer).
  String exportBikesCsv() {
    String cell(String v) =>
        RegExp(r'[",\n\r]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    String day(DateTime? d) =>
        d == null ? '' : d.toIso8601String().substring(0, 10);
    final rows = [
      [
        'Frame number',
        'Model',
        'Dealer',
        'City',
        'Status',
        'Placed',
        'Price',
        'Sold',
        'Sale price',
        'Paid',
        'Returned',
        'Notes',
      ],
      for (final b in _bikes)
        [
          b.frameNumber,
          b.model,
          _dealerName(b.contactId),
          contactById(b.contactId)?.city ?? '',
          b.status.label,
          day(b.placedAt),
          b.price.toStringAsFixed(2),
          day(b.soldAt),
          b.salePrice?.toStringAsFixed(2) ?? '',
          b.status == ConsignmentStatus.sold ? (b.paid ? 'yes' : 'no') : '',
          day(b.returnedAt),
          b.notes,
        ],
    ];
    return rows.map((r) => r.map(cell).join(',')).join('\n');
  }

  // ------------------------------------------------------------------- tasks

  Task addTask({
    required String title,
    required DateTime due,
    String? contactId,
  }) {
    final task = Task(
      id: _newId(),
      title: title,
      due: due,
      contactId: contactId,
    );
    _tasks.add(task);
    _changed();
    return task;
  }

  void updateTask(Task updated) {
    final index = _tasks.indexWhere((t) => t.id == updated.id);
    if (index < 0) return;
    _tasks[index] = updated;
    _changed();
  }

  void toggleTask(String id, bool done) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    _tasks[index] = task.copyWith(done: done);
    if (done && task.contactId != null) {
      _log(task.contactId, 'task completed: ${task.title}');
    }
    _changed();
  }

  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _changed();
  }

  // ------------------------------------------------------------------- stats

  List<Deal> get openDeals => _deals.where((d) => d.stage.isOpen).toList();

  double get openPipelineValue =>
      openDeals.fold(0, (sum, deal) => sum + deal.value);

  double get wonValue => _deals
      .where((d) => d.stage == DealStage.gewonnen)
      .fold(0, (sum, deal) => sum + deal.value);

  int countInStage(DealStage stage) =>
      _deals.where((d) => d.stage == stage).length;

  double valueInStage(DealStage stage) => _deals
      .where((d) => d.stage == stage)
      .fold(0, (sum, deal) => sum + deal.value);

  /// Won / (won + lost), or null when nothing has been closed yet.
  double? get conversionRate {
    final won = countInStage(DealStage.gewonnen);
    final closed = won + countInStage(DealStage.verloren);
    return closed == 0 ? null : won / closed;
  }

  /// Dealers with this status.
  int countWithStatus(ContactStatus status) =>
      contacts.where((c) => c.status == status).length;

  /// Dealers added this month.
  int get contactsAddedThisMonth {
    final n = now();
    return contacts
        .where(
          (c) => c.createdAt.year == n.year && c.createdAt.month == n.month,
        )
        .length;
  }

  List<Task> get openTasks =>
      _tasks.where((t) => !t.done).toList()
        ..sort((a, b) => a.due.compareTo(b.due));

  /// Open tasks that are overdue or due today.
  int get urgentTaskCount {
    final endOfToday = dateOnly(now()).add(const Duration(days: 1));
    return _tasks.where((t) => !t.done && t.due.isBefore(endOfToday)).length;
  }

  // -------------------------------------------------------------- demo data

  Future<void> resetToDemo() async {
    _seedDemo();
    _changed();
  }

  Future<void> clearAll() async {
    _contacts = [];
    _deals = [];
    _tasks = [];
    _activities = [];
    _products = [];
    _bikes = [];
    _changed();
  }

  void _seedDemo() {
    final n = now();
    final today = dateOnly(n);
    DateTime daysAgo(int d, [int hour = 10]) =>
        today.subtract(Duration(days: d)).add(Duration(hours: hour));
    DateTime at(int dayOffset, int hour, [int minute = 0]) =>
        today.add(Duration(days: dayOffset, hours: hour, minutes: minute));

    // Fictional demo dealers (".example" domains).
    _contacts = [
      Contact(
        id: 'c-alpen',
        name: 'Alpenrad Velos',
        type: ShopType.ebike,
        contactPerson: 'Martina Keller',
        city: 'Thun',
        email: 'martina@alpenrad.example',
        phone: '+41 33 555 01 10',
        website: 'alpenrad.example',
        status: ContactStatus.lead,
        createdAt: daysAgo(0, 8),
        notes:
            'Interested in fatbikes for winter rentals. Wants a demo bike '
            'before ordering.',
      ),
      Contact(
        id: 'c-trotti',
        name: 'TrottiCity Lausanne',
        type: ShopType.trottinette,
        contactPerson: 'Luca Moreau',
        city: 'Lausanne',
        email: 'luca@trotticity.example',
        phone: '+41 21 555 02 20',
        website: 'trotticity.example',
        status: ContactStatus.klant,
        createdAt: daysAgo(1),
      ),
      Contact(
        id: 'c-seeland',
        name: 'E-Bike Atelier Seeland',
        type: ShopType.ebike,
        contactPerson: 'Reto Gerber',
        city: 'Biel/Bienne',
        email: 'reto@atelier-seeland.example',
        phone: '+41 32 555 03 30',
        website: 'atelier-seeland.example',
        status: ContactStatus.lead,
        createdAt: daysAgo(3),
      ),
      Contact(
        id: 'c-rhein',
        name: 'Rheinrad Basel',
        type: ShopType.both,
        contactPerson: 'Sandra Meier',
        city: 'Basel',
        email: 'sandra@rheinrad.example',
        phone: '+41 61 555 04 40',
        website: 'rheinrad.example',
        status: ContactStatus.klant,
        createdAt: daysAgo(5),
      ),
      Contact(
        id: 'c-lago',
        name: 'Lago Scooters Lugano',
        type: ShopType.trottinette,
        contactPerson: 'Marco Bernasconi',
        city: 'Lugano',
        email: 'marco@lagoscooters.example',
        phone: '+41 91 555 05 50',
        website: 'lagoscooters.example',
        status: ContactStatus.partner,
        createdAt: daysAgo(6),
      ),
    ];

    // Example catalog: replace with your real models and dealer prices.
    _products = [
      Product(id: 'p-efat26', name: 'E-Fatbike 26″', sku: 'EF-26', price: 2500),
      Product(id: 'p-fat26', name: 'Fatbike 26″', sku: 'FB-26', price: 1490),
      Product(
        id: 'p-fat20',
        name: 'Kids Fatbike 20″',
        sku: 'FB-20',
        price: 890,
      ),
      Product(id: 'p-acc', name: 'Accessory pack', sku: 'ACC-1', price: 185),
    ];

    // Demo consignment bikes (fictional frame numbers).
    BikeEvent placed(String dealer, DateTime at) =>
        BikeEvent(at: at, text: 'Placed at $dealer');
    _bikes = [
      ConsignedBike(
        id: 'b-1',
        frameNumber: 'MSF26E-240311',
        model: 'E-Fatbike 26″',
        productId: 'p-efat26',
        contactId: 'c-rhein',
        placedAt: daysAgo(40),
        price: 2500,
        history: [placed('Rheinrad Basel', daysAgo(40))],
      ),
      ConsignedBike(
        id: 'b-2',
        frameNumber: 'MSF26E-240312',
        model: 'E-Fatbike 26″',
        productId: 'p-efat26',
        contactId: 'c-rhein',
        placedAt: daysAgo(40),
        price: 2500,
        history: [placed('Rheinrad Basel', daysAgo(40))],
      ),
      ConsignedBike(
        id: 'b-3',
        frameNumber: 'MSF26E-240298',
        model: 'E-Fatbike 26″',
        productId: 'p-efat26',
        contactId: 'c-rhein',
        placedAt: daysAgo(40),
        price: 2500,
        status: ConsignmentStatus.sold,
        soldAt: daysAgo(6),
        salePrice: 3290,
        history: [
          placed('Rheinrad Basel', daysAgo(40)),
          BikeEvent(at: daysAgo(6), text: 'Sold by Rheinrad Basel'),
        ],
      ),
      ConsignedBike(
        id: 'b-4',
        frameNumber: 'MSF26-231187',
        model: 'Fatbike 26″',
        productId: 'p-fat26',
        contactId: 'c-trotti',
        placedAt: daysAgo(25),
        price: 1490,
        history: [placed('TrottiCity Lausanne', daysAgo(25))],
      ),
      ConsignedBike(
        id: 'b-5',
        frameNumber: 'MSF20-230542',
        model: 'Kids Fatbike 20″',
        productId: 'p-fat20',
        contactId: 'c-trotti',
        placedAt: daysAgo(60),
        price: 890,
        status: ConsignmentStatus.returned,
        returnedAt: daysAgo(15),
        history: [
          placed('TrottiCity Lausanne', daysAgo(60)),
          BikeEvent(at: daysAgo(15), text: 'Returned by TrottiCity Lausanne'),
        ],
      ),
    ];

    _deals = [
      Deal(
        id: 'd-1',
        contactId: 'c-alpen',
        title: 'Demo fleet – 3 fatbikes',
        value: 7500,
        stage: DealStage.voorstel,
        createdAt: daysAgo(0, 9),
        items: const [
          DealItem(
            productId: 'p-efat26',
            name: 'E-Fatbike 26″',
            quantity: 3,
            unitPrice: 2500,
          ),
        ],
      ),
      Deal(
        id: 'd-2',
        contactId: 'c-trotti',
        title: 'Spring order 2027',
        value: 12400,
        stage: DealStage.inGesprek,
        createdAt: daysAgo(1),
      ),
      Deal(
        id: 'd-3',
        contactId: 'c-seeland',
        title: 'Dealer starter pack',
        value: 4900,
        stage: DealStage.nieuw,
        createdAt: daysAgo(3),
      ),
      Deal(
        id: 'd-4',
        contactId: 'c-rhein',
        title: 'Autumn order – 10 fatbikes',
        value: 24000,
        stage: DealStage.gewonnen,
        createdAt: daysAgo(20),
        closedAt: daysAgo(5),
        items: const [
          DealItem(
            productId: 'p-efat26',
            name: 'E-Fatbike 26″',
            quantity: 10,
            unitPrice: 2400,
          ),
        ],
      ),
      Deal(
        id: 'd-5',
        contactId: 'c-trotti',
        title: 'Accessories restock',
        value: 1850,
        stage: DealStage.gewonnen,
        createdAt: daysAgo(14),
        closedAt: daysAgo(1),
        items: const [
          DealItem(
            productId: 'p-acc',
            name: 'Accessory pack',
            quantity: 10,
            unitPrice: 185,
          ),
        ],
      ),
      Deal(
        id: 'd-6',
        contactId: 'c-lago',
        title: 'Showroom partnership',
        value: 3200,
        stage: DealStage.verloren,
        createdAt: daysAgo(10),
        closedAt: daysAgo(4),
      ),
    ];

    _tasks = [
      Task(
        id: 't-1',
        title: 'Call Martina about the demo fleet',
        due: at(0, 11, 30),
        contactId: 'c-alpen',
      ),
      Task(
        id: 't-2',
        title: 'Send 2027 price list to TrottiCity',
        due: at(0, 14),
        contactId: 'c-trotti',
        done: true,
      ),
      Task(
        id: 't-3',
        title: 'Prepare visit to E-Bike Atelier Seeland',
        due: at(0, 16),
        contactId: 'c-seeland',
      ),
      Task(id: 't-4', title: 'Follow up on new dealer leads', due: at(1, 9)),
    ];

    _activities = [
      Activity(
        id: 'a-1',
        contactId: 'c-alpen',
        message: 'requested a demo bike',
        at: n.subtract(const Duration(minutes: 10)),
      ),
      Activity(
        id: 'a-2',
        contactId: 'c-trotti',
        message: 'opened the price list',
        at: n.subtract(const Duration(hours: 1)),
      ),
      Activity(
        id: 'a-3',
        contactId: 'c-seeland',
        message: 'was added as a dealer',
        at: n.subtract(const Duration(hours: 3)),
      ),
      Activity(
        id: 'a-4',
        contactId: 'c-alpen',
        kind: ActivityKind.email,
        message: 'Sent product sheet and dealer prices.',
        at: daysAgo(2, 15),
      ),
      Activity(
        id: 'a-5',
        contactId: 'c-rhein',
        kind: ActivityKind.call,
        message: 'Discussed the spring reorder; wants 6 more E-Fatbikes.',
        at: daysAgo(12, 11),
      ),
      Activity(
        id: 'a-6',
        contactId: 'c-trotti',
        kind: ActivityKind.visit,
        message: 'Visited the shop. Good spot near the station.',
        at: daysAgo(20, 14),
      ),
    ];
  }
}

/// Makes the [CrmStore] available to the widget tree and rebuilds on change.
class CrmScope extends InheritedNotifier<CrmStore> {
  const CrmScope({super.key, required CrmStore store, required super.child})
    : super(notifier: store);

  static CrmStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CrmScope>()!.notifier!;

  /// Access without subscribing to rebuilds (for callbacks).
  static CrmStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CrmScope>()!.notifier!;
}
