import 'format.dart';

enum ContactStatus {
  lead('Lead'),
  klant('Customer'),
  partner('Partner'),

  /// Sells our bikes on consignment (dépôt-vente).
  depotVente('Dépôt-vente');

  const ContactStatus(this.label);
  final String label;

  /// Statuses a private customer can have (partners and dépôt-vente
  /// dealers are always shops).
  static const forPrivate = [lead, klant];

  /// The statuses that fit [kind].
  static List<ContactStatus> optionsFor(ContactKind kind) =>
      kind == ContactKind.person ? forPrivate : values;
}

enum DealStage {
  nieuw('New'),
  inGesprek('In talks'),
  voorstel('Proposal'),
  gewonnen('Won'),
  verloren('Lost');

  const DealStage(this.label);
  final String label;

  bool get isOpen => this != gewonnen && this != verloren;

  /// Stages shown in the pipeline (lost deals are kept out of it).
  static const pipeline = [nieuw, inGesprek, voorstel, gewonnen];
}

/// What a dealer sells.
enum ShopType {
  ebike('E-bikes'),
  trottinette('Trottinettes'),
  both('E-bikes & trottinettes'),
  unknown('Type not set');

  const ShopType(this.label);
  final String label;

  /// Guesses the type from a shop's name and website. Only answers when a
  /// clear keyword is present; everything else stays [unknown].
  static ShopType guess(String name, String website) {
    final text = '$name $website'.toLowerCase();
    final scooter = RegExp(r'trott|scoot|roller|monowheel|monoticino|inmotion')
        .hasMatch(text);
    final bike = RegExp(
      r'bike|biking|velo|vélo|cycl|cicli|bici|bicy|\brad|2rad|zweirad|dreirad',
    ).hasMatch(text);
    if (scooter && bike) return both;
    if (scooter) return trottinette;
    if (bike) return ebike;
    return unknown;
  }
}

/// Whether a contact is a shop or a person buying for themselves.
enum ContactKind {
  dealer('Dealer'),
  person('Private customer');

  const ContactKind(this.label);
  final String label;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

/// A dealer (shop) or a private customer ([kind]). Most of the app is about
/// dealers; private customers only show up where deals do.
class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.status,
    required this.createdAt,
    this.kind = ContactKind.dealer,
    this.type = ShopType.unknown,
    this.contactPerson = '',
    this.street = '',
    this.postalCode = '',
    this.city = '',
    this.website = '',
    this.notes = '',
    this.depotMargin,
    this.stockMargin,
  });

  /// Margin a partner keeps on a dépôt-vente bike when no rate is set.
  static const defaultDepotMargin = 20.0;

  final String id;
  final ContactKind kind;

  /// Shop name, or the person's full name for a private customer.
  final String name;
  final ShopType type;
  final String contactPerson;
  final String street;
  final String postalCode;
  final String city;
  final String email;
  final String phone;
  final String website;
  final ContactStatus status;
  final DateTime createdAt;
  final String notes;

  /// The partner's margin in percent of the retail price on dépôt-vente
  /// bikes. Null: [defaultDepotMargin].
  final double? depotMargin;

  /// The partner's margin in percent of the retail price on bikes they buy
  /// for their own stock. Null: not agreed yet, deals use retail prices.
  final double? stockMargin;

  bool get isPrivate => kind == ContactKind.person;

  /// Dépôt-vente margin in effect (0 for private customers).
  double get effectiveDepotMargin =>
      isPrivate ? 0 : depotMargin ?? defaultDepotMargin;

  /// Own-stock margin in effect (0 for private customers or when not set).
  double get effectiveStockMargin => isPrivate ? 0 : stockMargin ?? 0;

  /// `https://www.shop.ch/` → `shop.ch`
  String get websiteLabel => website
      .trim()
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/$'), '');

  /// Website as an openable URL, or null when there is none.
  Uri? get websiteUri {
    final w = website.trim();
    if (w.isEmpty) return null;
    return Uri.tryParse(
      RegExp(r'^https?://', caseSensitive: false).hasMatch(w)
          ? w
          : 'https://$w',
    );
  }

  /// "Bahnhofstrasse 1, 3000 Bern", or as much of it as is known.
  String get fullAddress => [
    street,
    [postalCode, city].where((p) => p.isNotEmpty).join(' '),
  ].where((p) => p.isNotEmpty).join(', ');

  /// Google Maps search for this shop, or null without an address.
  Uri? get mapUri {
    if (fullAddress.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$name, $fullAddress',
    });
  }

  /// "Bern · E-bikes" style summary line.
  String get summary => [
    if (city.isNotEmpty) city,
    if (type != ShopType.unknown) type.label,
  ].join(' · ');

  Contact copyWith({
    String? name,
    ShopType? type,
    String? contactPerson,
    String? street,
    String? postalCode,
    String? city,
    String? email,
    String? phone,
    String? website,
    ContactStatus? status,
    String? notes,
    double? Function()? depotMargin,
    double? Function()? stockMargin,
  }) => Contact(
    id: id,
    kind: kind,
    name: name ?? this.name,
    type: type ?? this.type,
    contactPerson: contactPerson ?? this.contactPerson,
    street: street ?? this.street,
    postalCode: postalCode ?? this.postalCode,
    city: city ?? this.city,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    status: status ?? this.status,
    createdAt: createdAt,
    notes: notes ?? this.notes,
    depotMargin: depotMargin == null ? this.depotMargin : depotMargin(),
    stockMargin: stockMargin == null ? this.stockMargin : stockMargin(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'type': type.name,
    'contactPerson': contactPerson,
    'street': street,
    'postalCode': postalCode,
    'city': city,
    'email': email,
    'phone': phone,
    'website': website,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    // Only written when set, so records without rates stay as they were.
    'depotMargin': ?depotMargin,
    'stockMargin': ?stockMargin,
  };

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
    id: json['id'] as String,
    kind: _enumByName(ContactKind.values, json['kind'], ContactKind.dealer),
    name: json['name'] as String? ?? '',
    type: _enumByName(ShopType.values, json['type'], ShopType.unknown),
    contactPerson: json['contactPerson'] as String? ?? '',
    street: json['street'] as String? ?? '',
    postalCode: json['postalCode'] as String? ?? '',
    city: json['city'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    website: json['website'] as String? ?? '',
    status: _enumByName(
      ContactStatus.values,
      json['status'],
      // Also catches the old "nieuw" (New) status, which became Lead.
      ContactStatus.lead,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    notes: json['notes'] as String? ?? '',
    depotMargin: (json['depotMargin'] as num?)?.toDouble(),
    stockMargin: (json['stockMargin'] as num?)?.toDouble(),
  );
}

/// What a partner pays for a bike: [retail] minus [marginPercent], rounded
/// to whole francs (prices are shown and typed in whole francs).
double partnerPrice(double retail, double marginPercent) =>
    (retail * (100 - marginPercent) / 100).roundToDouble();

/// "20%" style label for a margin rate.
String formatMargin(double percent) =>
    '${percent == percent.roundToDouble() ? percent.toInt() : percent}%';

/// One order line on a deal, e.g. 3 × E-Fatbike at CHF 2,500.
class DealItem {
  const DealItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.productId,
  });

  /// Product this line came from (null for free-text lines). The name and
  /// price are copied so later catalog changes don't alter old deals.
  final String? productId;
  final String name;
  final int quantity;
  final double unitPrice;

  double get total => quantity * unitPrice;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  factory DealItem.fromJson(Map<String, Object?> json) => DealItem(
    productId: json['productId'] as String?,
    name: json['name'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
  );
}

/// Name for a deal made from what is on it: `2 × Mooi, Storm`, or
/// `Deal of Nov 24, 2026` when it has no products.
String dealTitleFor(List<DealItem> items, DateTime date) {
  final qty = <String, int>{};
  for (final i in items) {
    final name = i.name.trim();
    if (name.isNotEmpty) qty[name] = (qty[name] ?? 0) + i.quantity;
  }
  if (qty.isEmpty) return 'Deal of ${formatDate(date)}';
  final parts = [
    for (final e in qty.entries) e.value > 1 ? '${e.value} × ${e.key}' : e.key,
  ];
  return parts.length <= 3
      ? parts.join(', ')
      : '${parts.take(2).join(', ')} + ${parts.length - 2} more';
}

class Deal {
  const Deal({
    required this.id,
    required this.contactId,
    required this.title,
    required double value,
    required this.stage,
    required this.createdAt,
    this.closedAt,
    this.items = const [],
  }) : _value = value; // ignore: prefer_initializing_formals

  final String id;
  final String contactId;
  final String title;
  final double _value;
  final DealStage stage;
  final DateTime createdAt;
  final DateTime? closedAt;
  final List<DealItem> items;

  /// Sum of the order lines when there are any, otherwise the entered value.
  double get value =>
      items.isEmpty ? _value : items.fold(0, (sum, i) => sum + i.total);

  int get units => items.fold(0, (sum, i) => sum + i.quantity);

  Deal copyWith({
    String? contactId,
    String? title,
    double? value,
    DealStage? stage,
    DateTime? Function()? closedAt,
    List<DealItem>? items,
  }) => Deal(
    id: id,
    contactId: contactId ?? this.contactId,
    title: title ?? this.title,
    value: value ?? _value,
    stage: stage ?? this.stage,
    createdAt: createdAt,
    closedAt: closedAt != null ? closedAt() : this.closedAt,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'contactId': contactId,
    'title': title,
    'value': value,
    'stage': stage.name,
    'createdAt': createdAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'items': [for (final i in items) i.toJson()],
  };

  factory Deal.fromJson(Map<String, Object?> json) => Deal(
    id: json['id'] as String,
    contactId: json['contactId'] as String,
    title: json['title'] as String? ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    stage: _enumByName(DealStage.values, json['stage'], DealStage.nieuw),
    createdAt: DateTime.parse(json['createdAt'] as String),
    closedAt: json['closedAt'] == null
        ? null
        : DateTime.parse(json['closedAt'] as String),
    items: [
      for (final i in (json['items'] as List?) ?? const [])
        DealItem.fromJson((i as Map).cast<String, Object?>()),
    ],
  );
}

/// An item in the product catalog (e.g. a fatbike model).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.sku = '',
    this.category = '',
    this.active = true,
  });

  final String id;
  final String name;
  final String sku;

  /// Group in the shared catalog, e.g. "Fatbikes" or "Spare Parts".
  final String category;

  bool get isFatbike => category.trim().toLowerCase() == 'fatbikes';

  /// Price suggested for order lines (0 = no price yet). From the shared
  /// catalog this is the sales price incl. VAT.
  final double price;

  /// Inactive products stay on old deals but aren't offered for new ones.
  final bool active;

  Product copyWith({String? name, String? sku, double? price, bool? active}) =>
      Product(
        id: id,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        category: category,
        price: price ?? this.price,
        active: active ?? this.active,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sku': sku,
    'category': category,
    'price': price,
    'active': active,
  };

  factory Product.fromJson(Map<String, Object?> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    sku: json['sku'] as String? ?? '',
    category: json['category'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    active: json['active'] as bool? ?? true,
  );
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.due,
    this.contactId,
    this.done = false,
  });

  final String id;
  final String title;
  final DateTime due;
  final String? contactId;
  final bool done;

  Task copyWith({
    String? title,
    DateTime? due,
    String? Function()? contactId,
    bool? done,
  }) => Task(
    id: id,
    title: title ?? this.title,
    due: due ?? this.due,
    contactId: contactId != null ? contactId() : this.contactId,
    done: done ?? this.done,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'due': due.toIso8601String(),
    'contactId': contactId,
    'done': done,
  };

  factory Task.fromJson(Map<String, Object?> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    due: DateTime.parse(json['due'] as String),
    contactId: json['contactId'] as String?,
    done: json['done'] as bool? ?? false,
  );
}

/// What kind of timeline entry an [Activity] is.
enum ActivityKind {
  /// Written by the app (e.g. "was added as a dealer").
  system('Update'),
  call('Call'),
  visit('Visit'),
  email('Email'),
  note('Note');

  const ActivityKind(this.label);
  final String label;

  /// Kinds the user logs by hand.
  static const logged = [call, visit, email, note];
}

class Activity {
  const Activity({
    required this.id,
    required this.message,
    required this.at,
    this.contactId,
    this.kind = ActivityKind.system,
  });

  final String id;
  final String? contactId;
  final ActivityKind kind;

  /// For system entries: shown after the dealer's name, e.g. "was added as a
  /// dealer". For logged entries: the user's note.
  final String message;
  final DateTime at;

  bool get isInteraction => kind != ActivityKind.system;

  Map<String, Object?> toJson() => {
    'id': id,
    'contactId': contactId,
    'kind': kind.name,
    'message': message,
    'at': at.toIso8601String(),
  };

  factory Activity.fromJson(Map<String, Object?> json) => Activity(
    id: json['id'] as String,
    contactId: json['contactId'] as String?,
    kind: _enumByName(ActivityKind.values, json['kind'], ActivityKind.system),
    message: json['message'] as String? ?? '',
    at: DateTime.parse(json['at'] as String),
  );
}

enum ConsignmentStatus {
  atDealer('At dealer'),
  sold('Sold'),
  returned('Returned');

  const ConsignmentStatus(this.label);
  final String label;
}

/// One entry in a consignment bike's history ("Placed at X", "Sold", …).
class BikeEvent {
  const BikeEvent({required this.at, required this.text});

  final DateTime at;
  final String text;

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'text': text};

  factory BikeEvent.fromJson(Map<String, Object?> json) => BikeEvent(
    at: DateTime.parse(json['at'] as String),
    text: json['text'] as String? ?? '',
  );
}

/// A bike placed at a dealer on consignment (dépôt-vente), tracked by its
/// frame number.
/// The bike models placed at dealers on consignment, with the price per bike.
const consignmentModels = [
  (name: 'Mooi', price: 2690.0),
  (name: 'Brommer', price: 2490.0),
  (name: 'Dapper Pro', price: 2490.0),
  (name: 'Storm', price: 2690.0),
];

/// One bike to place: see `CrmStore.placeBikeBatch`.
typedef NewBike = ({
  String frameNumber,
  String model,
  String? productId,
  double price,
});

class ConsignedBike {
  const ConsignedBike({
    required this.id,
    required this.frameNumber,
    required this.model,
    required this.contactId,
    required this.placedAt,
    this.productId,
    this.price = 0,
    this.status = ConsignmentStatus.atDealer,
    this.soldAt,
    this.salePrice,
    this.paid = false,
    this.returnedAt,
    this.notes = '',
    this.history = const [],
  });

  final String id;
  final String frameNumber;

  /// Model name (copied from the product so catalog changes don't alter it).
  final String model;
  final String? productId;

  /// Dealer currently (or last) holding the bike.
  final String contactId;
  final DateTime placedAt;

  /// Agreed consignment price the dealer pays when the bike is sold.
  final double price;
  final ConsignmentStatus status;
  final DateTime? soldAt;

  /// What the dealer reported selling it for (optional).
  final double? salePrice;

  /// Whether the dealer has paid Molenstraat for a sold bike.
  final bool paid;
  final DateTime? returnedAt;
  final String notes;
  final List<BikeEvent> history;

  bool get isAtDealer => status == ConsignmentStatus.atDealer;
  bool get awaitingPayment => status == ConsignmentStatus.sold && !paid;

  /// Normalized frame number for comparisons: no spaces/dashes, upper case.
  static String normalizeFrame(String frame) =>
      frame.toUpperCase().replaceAll(RegExp(r'[\s\-_./]'), '');

  ConsignedBike copyWith({
    String? frameNumber,
    String? model,
    String? Function()? productId,
    String? contactId,
    DateTime? placedAt,
    double? price,
    ConsignmentStatus? status,
    DateTime? Function()? soldAt,
    double? Function()? salePrice,
    bool? paid,
    DateTime? Function()? returnedAt,
    String? notes,
    List<BikeEvent>? history,
  }) => ConsignedBike(
    id: id,
    frameNumber: frameNumber ?? this.frameNumber,
    model: model ?? this.model,
    productId: productId != null ? productId() : this.productId,
    contactId: contactId ?? this.contactId,
    placedAt: placedAt ?? this.placedAt,
    price: price ?? this.price,
    status: status ?? this.status,
    soldAt: soldAt != null ? soldAt() : this.soldAt,
    salePrice: salePrice != null ? salePrice() : this.salePrice,
    paid: paid ?? this.paid,
    returnedAt: returnedAt != null ? returnedAt() : this.returnedAt,
    notes: notes ?? this.notes,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'frameNumber': frameNumber,
    'model': model,
    'productId': productId,
    'contactId': contactId,
    'placedAt': placedAt.toIso8601String(),
    'price': price,
    'status': status.name,
    'soldAt': soldAt?.toIso8601String(),
    'salePrice': salePrice,
    'paid': paid,
    'returnedAt': returnedAt?.toIso8601String(),
    'notes': notes,
    'history': [for (final e in history) e.toJson()],
  };

  factory ConsignedBike.fromJson(Map<String, Object?> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return ConsignedBike(
      id: json['id'] as String,
      frameNumber: json['frameNumber'] as String? ?? '',
      model: json['model'] as String? ?? '',
      productId: json['productId'] as String?,
      contactId: json['contactId'] as String,
      placedAt: DateTime.parse(json['placedAt'] as String),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      status: _enumByName(
        ConsignmentStatus.values,
        json['status'],
        ConsignmentStatus.atDealer,
      ),
      soldAt: date('soldAt'),
      salePrice: (json['salePrice'] as num?)?.toDouble(),
      paid: json['paid'] as bool? ?? false,
      returnedAt: date('returnedAt'),
      notes: json['notes'] as String? ?? '',
      history: [
        for (final e in (json['history'] as List?) ?? const [])
          BikeEvent.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }
}
