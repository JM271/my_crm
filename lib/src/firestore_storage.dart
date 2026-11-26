import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'crm_store.dart';

/// Stores the CRM in Cloud Firestore, one document per record, inside the
/// workshop shared with the other Molenstraat apps (Inventory, Offers):
///
///   workshops/molenstraat/crmContacts/{id}    dealers, private customers
///   workshops/molenstraat/crmDeals/{id}       … and crmTasks, crmActivities,
///                                             crmBikes
///   workshops/molenstraat/crmConfig/settings  shared settings (currency)
///   workshops/molenstraat/crmProfiles/{uid}   per-user name + email
///
/// Products are read (never written) from the catalog shared with the Offers
/// and Inventory apps: `products` (the Molenstraat list with sales prices),
/// `catalog` (products added in Inventory) and `partPrices` (prices for
/// products without a catalog price). They are edited in those apps.
///
/// Who may read and write is decided by workshops/molenstraat/members/{uid}
/// (role admin or editor), the same approval as the other apps. The security
/// rules live in the Inventory repository's firestore.rules.
///
/// The store hands over its full state as JSON (same format as a backup);
/// this class works out which documents changed and writes only those, so
/// two people editing different records don't overwrite each other.
/// [changes] streams the state again whenever someone else edits it.
class FirestoreStorage extends CrmStorage {
  FirestoreStorage({
    required this.db,
    required this.uid,
    required this.email,
    this.workshop = 'molenstraat',
  });

  final FirebaseFirestore db;
  final String uid;
  final String email;
  final String workshop;

  /// Backup sections stored in crm… collections (products are not: they
  /// come from the shared catalog).
  static const collections = [
    'contacts',
    'deals',
    'tasks',
    'activities',
    'bikes',
  ];

  /// Firestore collection holding a backup section, e.g. contacts →
  /// crmContacts. The prefix keeps CRM data apart from the other apps'
  /// collections (Inventory also has `products`).
  static String collectionFor(String section) =>
      'crm${section[0].toUpperCase()}${section.substring(1)}';

  DocumentReference<Map<String, dynamic>> get _root =>
      db.collection('workshops').doc(workshop);
  CollectionReference<Map<String, dynamic>> _col(String section) =>
      _root.collection(collectionFor(section));
  DocumentReference<Map<String, dynamic>> get _settings =>
      _root.collection('crmConfig').doc('settings');
  DocumentReference<Map<String, dynamic>> get _profile =>
      _root.collection('crmProfiles').doc(uid);

  // Last known server state, per collection: id → encoded document. Used to
  // compute the minimal set of writes on save.
  final Map<String, Map<String, Map<String, dynamic>>> _docs = {
    for (final c in collections) c: {},
  };
  String _currency = 'CHF';
  String? _userName;

  // The shared catalog, as last read: id → document.
  Map<String, Map<String, dynamic>> _catalog = {};
  Map<String, Map<String, dynamic>> _customCatalog = {};
  Map<String, Map<String, dynamic>> _partPrices = {};

  @override
  bool get sharedCatalog => true;

  CollectionReference<Map<String, dynamic>> _shared(String name) =>
      _root.collection(name);

  static String _skuKey(String sku) => sku.trim().toUpperCase();

  /// The shared catalog as CRM products, Fatbikes first like in the Offers
  /// app. A product without a catalog price gets its price from partPrices.
  List<Map<String, dynamic>> _products() {
    final prices = <String, int>{
      for (final d in _partPrices.values)
        if (d['sku'] case final String sku)
          _skuKey(sku): (d['priceCents'] as num?)?.toInt() ?? 0,
    };
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    void add(String id, Map<String, dynamic> d) {
      final sku = (d['sku'] is String ? d['sku'] as String : '').trim();
      final name = (d['name'] is String ? d['name'] as String : '').trim();
      if (sku.isEmpty || name.isEmpty || !seen.add(_skuKey(sku))) return;
      var cents = (d['priceCents'] as num?)?.toInt() ?? 0;
      if (cents <= 0) cents = prices[_skuKey(sku)] ?? 0;
      out.add({
        'id': id,
        'name': name,
        'sku': sku,
        'category': (d['category'] is String ? d['category'] as String : '')
            .trim(),
        'price': cents / 100,
        'active': true,
      });
    }

    _catalog.forEach(add);
    // Inventory's own products; their ids could match a catalog id.
    _customCatalog.forEach((id, d) => add('catalog-$id', d));
    const groups = ['Fatbikes', 'Spare Parts', 'Accessoires'];
    int rank(Map<String, dynamic> p) {
      final i = groups.indexOf(p['category'] as String);
      return i < 0 ? groups.length : i;
    }

    return out..sort((a, b) {
      final byGroup = rank(a).compareTo(rank(b));
      return byGroup != 0
          ? byGroup
          : (a['sku'] as String).compareTo(b['sku'] as String);
    });
  }

  static Map<String, Map<String, dynamic>> _byId(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) => {for (final d in snap.docs) d.id: d.data()};

  /// True when the workspace had no records at all when loaded.
  bool get wasEmpty => _wasEmpty;
  bool _wasEmpty = false;

  @override
  bool get seedDemoWhenEmpty => false;

  String _defaultName() {
    final local = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    return local.isEmpty
        ? 'Me'
        : local
              .split(' ')
              .where((p) => p.isNotEmpty)
              .map((p) => p[0].toUpperCase() + p.substring(1))
              .join(' ');
  }

  String _assemble() => jsonEncode({
    'app': 'molenstraat-crm',
    'version': 2,
    'settings': {
      'userName': _userName ?? _defaultName(),
      'currency': _currency,
    },
    for (final c in collections) c: _docs[c]!.values.toList(),
    'products': _products(),
  });

  @override
  Future<String?> load() async {
    final results = await Future.wait([
      for (final c in collections) _col(c).get(),
    ]);
    for (var i = 0; i < collections.length; i++) {
      _docs[collections[i]] = {for (final d in results[i].docs) d.id: d.data()};
    }
    final shared = await Future.wait([
      _shared('products').get(),
      _shared('catalog').get(),
      _shared('partPrices').get(),
    ]);
    _catalog = _byId(shared[0]);
    _customCatalog = _byId(shared[1]);
    _partPrices = _byId(shared[2]);
    final settings = await _settings.get();
    _currency = (settings.data()?['currency'] as String?) ?? 'CHF';
    final profile = await _profile.get();
    _userName = profile.data()?['name'] as String?;
    _wasEmpty = _docs.values.every((m) => m.isEmpty);
    return _assemble();
  }

  @override
  Future<void> save(String data) async {
    final json = jsonDecode(data) as Map<String, dynamic>;
    final ops = <void Function(WriteBatch)>[];

    for (final c in collections) {
      final incoming = <String, Map<String, dynamic>>{
        for (final e in (json[c] as List? ?? const []))
          (e as Map)['id'] as String: e.cast<String, dynamic>(),
      };
      final known = _docs[c]!;
      incoming.forEach((id, doc) {
        if (!_sameJson(known[id], doc)) {
          ops.add((b) => b.set(_col(c).doc(id), doc));
        }
      });
      for (final id in known.keys) {
        if (!incoming.containsKey(id)) {
          ops.add((b) => b.delete(_col(c).doc(id)));
        }
      }
      _docs[c] = incoming;
    }

    final settings = (json['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final currency = settings['currency'] as String? ?? _currency;
    if (currency != _currency) {
      _currency = currency;
      ops.add((b) => b.set(_settings, {'currency': currency}));
    }
    final name = settings['userName'] as String?;
    if (name != null && name != (_userName ?? _defaultName())) {
      _userName = name;
      ops.add((b) => b.set(_profile, {'name': name, 'email': email}));
    }

    // Firestore allows at most 500 writes per batch.
    for (var i = 0; i < ops.length; i += 450) {
      final batch = db.batch();
      for (final op in ops.skip(i).take(450)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  static bool _sameJson(Map<String, dynamic>? a, Map<String, dynamic> b) =>
      a != null && canonicalJson(a) == canonicalJson(b);

  /// JSON with map keys sorted at every level. Firestore does not keep the
  /// field order a record was written in, so plain jsonEncode would see
  /// every record loaded from the database as changed and rewrite it.
  static String canonicalJson(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? v) => switch (v) {
    Map() => {
      for (final k in (v.keys.map((k) => '$k').toList()..sort()))
        k: _sorted(v[k]),
    },
    List() => [for (final e in v) _sorted(e)],
    // Firestore may hand back 2500.0 as the int 2500 (or vice versa).
    double() when v == v.roundToDouble() && v.abs() < 1e15 => v.toInt(),
    _ => v,
  };

  StreamController<String>? _controller;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _debounce;

  @override
  Stream<String>? get changes {
    if (_controller != null) return _controller!.stream;
    final controller = StreamController<String>.broadcast(
      onCancel: () {
        for (final s in _subs) {
          s.cancel();
        }
        _subs.clear();
        _debounce?.cancel();
        _controller = null;
      },
    );
    _controller = controller;

    void emitSoon() {
      // Several collections often change together (e.g. a deal + activity);
      // send one update for all of them.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 60), () {
        if (!controller.isClosed) controller.add(_assemble());
      });
    }

    for (final c in collections) {
      _subs.add(
        _col(c).snapshots().listen((snap) {
          _docs[c] = {for (final d in snap.docs) d.id: d.data()};
          emitSoon();
        }),
      );
    }
    void watchShared(
      String name,
      void Function(Map<String, Map<String, dynamic>>) apply,
    ) {
      _subs.add(
        _shared(name).snapshots().listen((snap) {
          apply(_byId(snap));
          emitSoon();
        }),
      );
    }

    watchShared('products', (m) => _catalog = m);
    watchShared('catalog', (m) => _customCatalog = m);
    watchShared('partPrices', (m) => _partPrices = m);
    _subs.add(
      _settings.snapshots().listen((snap) {
        _currency = (snap.data()?['currency'] as String?) ?? _currency;
        emitSoon();
      }),
    );
    return controller.stream;
  }
}
