import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/firestore_storage.dart';
import 'package:my_crm/src/models.dart';

DateTime fixedNow() => DateTime(2026, 11, 23, 9);

Future<(CrmStore, FirestoreStorage)> open(
  FakeFirebaseFirestore db, {
  String uid = 'u1',
  String email = 'jonas@example.ch',
}) async {
  final storage = FirestoreStorage(db: db, uid: uid, email: email);
  final store = CrmStore(storage: storage, clock: fixedNow);
  await store.load();
  return (store, storage);
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  test('an empty online database stays empty (no demo data)', () async {
    final db = FakeFirebaseFirestore();
    final (store, storage) = await open(db);
    expect(store.contacts, isEmpty);
    expect(storage.wasEmpty, isTrue);
    // Default name comes from the email.
    expect(store.userName, 'Jonas');
  });

  test(
    'records are stored one document each and load on another device',
    () async {
      final db = FakeFirebaseFirestore();
      final (a, _) = await open(db);
      a.addContact(name: 'Velo Neu', city: 'Chur', type: ShopType.ebike);
      a.placeBikes(
        contactId: a.contacts.single.id,
        frameNumbers: ['FN-1', 'FN-2'],
        model: 'E-Fatbike 26″',
        price: 2500,
      );
      await settle();

      final dealers = await db
          .collection('workshops/molenstraat/crmContacts')
          .get();
      expect(dealers.docs.single.data()['name'], 'Velo Neu');
      final bikes = await db.collection('workshops/molenstraat/crmBikes').get();
      expect(bikes.docs.length, 2);

      final (b, storageB) = await open(db, uid: 'u2', email: 'anna@example.ch');
      expect(storageB.wasEmpty, isFalse);
      expect(b.contacts.single.city, 'Chur');
      expect(b.bikesAtDealers.length, 2);
      expect(b.userName, 'Anna');
    },
  );

  test('deletes and edits reach the database', () async {
    final db = FakeFirebaseFirestore();
    final (a, _) = await open(db);
    final shop = a.addContact(name: 'Shop A');
    a.addContact(name: 'Shop B');
    await settle();
    a.updateContact(shop.copyWith(city: 'Bern'));
    a.deleteContact(a.contacts.firstWhere((c) => c.name == 'Shop B').id);
    await settle();

    final docs = await db.collection('workshops/molenstraat/crmContacts').get();
    expect(docs.docs.map((d) => d.data()['name']), ['Shop A']);
    expect(docs.docs.single.data()['city'], 'Bern');
  });

  test("another device's edits show up live", () async {
    final db = FakeFirebaseFirestore();
    final (a, _) = await open(db);
    final (b, _) = await open(db, uid: 'u2', email: 'anna@example.ch');
    expect(b.contacts, isEmpty);

    a.addContact(name: 'Live Shop');
    await settle();
    expect(b.contacts.map((c) => c.name), ['Live Shop']);

    b.logInteraction(
      contactId: b.contacts.single.id,
      kind: ActivityKind.call,
      note: 'Called from the phone',
    );
    await settle();
    expect(a.lastContactAt(a.contacts.single.id), isNotNull);
  });

  test('currency is shared, the name is per person', () async {
    final db = FakeFirebaseFirestore();
    final (a, _) = await open(db);
    a.updateSettings(userName: 'Jonas Mühle', currency: 'EUR');
    await settle();
    final (b, _) = await open(db, uid: 'u2', email: 'anna@example.ch');
    expect(b.currency, 'EUR');
    expect(b.userName, 'Anna');
    expect(
      (await db.doc('workshops/molenstraat/crmConfig/settings').get()).data(),
      {'currency': 'EUR'},
    );
    expect(
      (await db.doc('workshops/molenstraat/crmProfiles/u1').get()).data(),
      {'name': 'Jonas Mühle', 'email': 'jonas@example.ch'},
    );
    b.updateSettings(currency: 'CHF'); // reset global formatter
  });

  test('products come from the catalog shared with the Offers app', () async {
    final db = FakeFirebaseFirestore();
    final ws = 'workshops/molenstraat';
    await db.doc('$ws/products/MS-FB-1001').set({
      'sku': 'MS-FB-1001',
      'name': 'Fatbike Mooi',
      'category': 'Fatbikes',
      'priceCents': 269000,
    });
    await db.doc('$ws/products/MS-FB-1002').set({
      'sku': 'MS-FB-1002',
      'name': 'Fatbike Brommer',
      'category': 'Fatbikes',
    });
    // A price for the product without catalog price, set in the Offers app.
    await db.doc('$ws/partPrices/MS-FB-1002').set({
      'sku': 'ms-fb-1002',
      'priceCents': 249000,
    });
    // Spare parts and accessories are left out of the CRM.
    await db.doc('$ws/products/MS-SP-3009').set({
      'sku': 'MS-SP-3009',
      'name': 'Brake pads',
      'category': 'Spare Parts',
      'priceCents': 2450,
    });
    await db.doc('$ws/catalog/OWN-1').set({
      'sku': 'OWN-1',
      'name': 'Phone holder',
      'category': 'Accessoires',
      'priceCents': 1990,
    });
    // A fatbike added in Inventory, and one that repeats a catalog SKU.
    await db.doc('$ws/catalog/OWN-2').set({
      'sku': 'OWN-2',
      'name': 'Fatbike Special',
      'category': 'Fatbikes',
      'priceCents': 300000,
    });
    await db.doc('$ws/catalog/dup').set({
      'sku': 'MS-FB-1001',
      'name': 'Duplicate',
      'category': '',
    });

    final (store, _) = await open(db);
    expect(store.productsReadOnly, isTrue);
    expect(store.products.map((p) => p.name), [
      'Fatbike Mooi',
      'Fatbike Brommer',
      'Fatbike Special',
    ]);
    expect(store.products[0].price, 2690);
    expect(store.products[1].price, 2490);
    expect(store.products[2].id, 'catalog-OWN-2');

    // Saving CRM data never writes products anywhere.
    store.addContact(name: 'Velo Neu');
    await settle();
    final catalog = await db.collection('$ws/products').get();
    expect(catalog.docs.length, 3);
    expect(catalog.docs.first.data().containsKey('price'), isFalse);
    final crm = await db.collection('$ws/crmProducts').get();
    expect(crm.docs, isEmpty);
    for (final c in FirestoreStorage.collections) {
      expect(FirestoreStorage.collectionFor(c), startsWith('crm'));
    }
  });

  test('a price change in the Offers app shows up live', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.doc('workshops/molenstraat/products/MS-FB-1004');
    await ref.set({
      'sku': 'MS-FB-1004',
      'name': 'Fatbike Storm',
      'category': 'Fatbikes',
      'priceCents': 269000,
    });
    final (store, _) = await open(db);
    await settle();
    await ref.update({'priceCents': 279000});
    await settle();
    expect(store.products.single.price, 2790);
  });

  test('restoring a backup uploads everything', () async {
    final local = CrmStore(storage: MemoryStorage(), clock: fixedNow);
    await local.load(); // demo data
    final db = FakeFirebaseFirestore();
    final (cloud, _) = await open(db);
    cloud.restoreBackup(local.exportBackup());
    await settle();
    final (other, _) = await open(db, uid: 'u2', email: 'anna@example.ch');
    expect(other.contacts.length, local.contacts.length);
    expect(other.deals.length, local.deals.length);
    expect(other.bikes.length, local.bikes.length);
    // A backup never replaces the shared catalog.
    expect(other.products, isEmpty);
    expect(
      (await db.collection('workshops/molenstraat/crmProducts').get()).docs,
      isEmpty,
    );
  });

  test(
    'records whose fields come back in another order are not rewritten',
    () async {
      final db = FakeFirebaseFirestore();
      // As the database might return it: fields sorted, 850.0 read back as 850.
      await db.doc('workshops/molenstraat/crmDeals/d1').set({
        'closedAt': null,
        'contactId': 'c1',
        'createdAt': '2026-06-17T20:04:38.408',
        'id': 'd1',
        'items': <Object>[],
        'stage': 'gewonnen',
        'title': 'crazy scoot',
        'value': 850,
      });
      await db.doc('workshops/molenstraat/crmContacts/c1').set({
        'id': 'c1',
        'name': 'Crazy Scoot',
        'type': 'trottinette',
        'status': 'klant',
        'createdAt': '2026-06-17T20:04:38.408',
      });
      final (store, _) = await open(db);
      var dealWrites = 0;
      final sub = db
          .doc('workshops/molenstraat/crmDeals/d1')
          .snapshots()
          .skip(1)
          .listen((_) => dealWrites++);
      store.addContact(name: 'Another shop');
      await settle();
      await sub.cancel();
      expect(dealWrites, 0);
      expect(
        FirestoreStorage.canonicalJson({
          'b': 1.0,
          'a': [
            {'y': 2, 'x': 1},
          ],
        }),
        '{"a":[{"x":1,"y":2}],"b":1}',
      );
    },
  );
}
