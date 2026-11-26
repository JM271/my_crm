import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/main.dart';
import 'package:my_crm/src/contact_import.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/models.dart';

DateTime fixedNow() => DateTime(2026, 11, 23, 9);

Future<CrmStore> loadStore([MemoryStorage? storage]) async {
  final store = CrmStore(storage: storage ?? MemoryStorage(), clock: fixedNow);
  await store.load();
  return store;
}

void main() {
  group('private customers in the store', () {
    test('are kept out of the dealer list and dealer stats', () async {
      final store = await loadStore();
      final dealers = store.contacts.length;
      final customers = store.countWithStatus(ContactStatus.klant);

      final anna = store.addContact(
        name: 'Anna Keller',
        kind: ContactKind.person,
        city: 'Thun',
        status: ContactStatus.klant,
      );

      expect(anna.isPrivate, isTrue);
      expect(store.contacts.length, dealers);
      expect(store.countWithStatus(ContactStatus.klant), customers);
      expect(store.privateCustomers.single.name, 'Anna Keller');
      expect(store.allContacts, contains(anna));
      expect(store.contactById(anna.id), anna);
      expect(store.exportDealersCsv(), isNot(contains('Anna Keller')));
    });

    test('can have deals, which promote them like dealers', () async {
      final store = await loadStore();
      final anna = store.addContact(
        name: 'Anna Keller',
        kind: ContactKind.person,
      );

      store.addDeal(
        contactId: anna.id,
        title: 'Fatbike',
        value: 2900,
        stage: DealStage.gewonnen,
      );

      expect(store.dealsFor(anna.id).single.title, 'Fatbike');
      expect(store.contactById(anna.id)!.status, ContactStatus.klant);
    });

    test('stay private after a reload', () async {
      final storage = MemoryStorage();
      final store = await loadStore(storage);
      store.addContact(name: 'Anna Keller', kind: ContactKind.person);
      await Future<void>.delayed(Duration.zero);

      final reloaded = await loadStore(storage);
      expect(reloaded.privateCustomers.single.name, 'Anna Keller');
      expect(
        reloaded.contacts.map((c) => c.name),
        isNot(contains('Anna Keller')),
      );
    });

    test('old records without a kind load as dealers', () {
      final c = Contact.fromJson({
        'id': 'c-old',
        'name': 'Velo Alt',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(c.kind, ContactKind.dealer);
    });

    test('an import never merges a shop into a private customer', () async {
      final store = await loadStore();
      store.addContact(name: 'Velo Muster', kind: ContactKind.person);

      final result = store.importContacts([
        const ContactDraft(name: 'Velo Muster', city: 'Bern'),
      ]);

      expect(result.added, 1);
      expect(store.privateCustomers.single.city, '');
      expect(
        store.contacts.where((c) => c.name == 'Velo Muster').single.city,
        'Bern',
      );
    });
  });

  testWidgets('a new deal can be made with a new private customer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await loadStore();
    await tester.pumpWidget(MolenstraatApp(store: store));

    // Deals page → New deal.
    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New deal').first);
    await tester.pumpAndSettle();

    // Create the customer from inside the deal form.
    await tester.tap(find.text('New private customer'));
    await tester.pumpAndSettle();
    expect(find.text('Shop name'), findsNothing);
    expect(find.text('Website'), findsNothing);
    await tester.tap(find.text('Add customer'));
    await tester.pump();
    expect(find.text('Please enter a name'), findsOneWidget);

    final dialog = find.ancestor(
      of: find.text('New private customer').last,
      matching: find.byType(AlertDialog),
    );
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Anna Keller');
    await tester.enterText(fields.at(1), '+41 79 123 45 67');
    await tester.tap(find.text('Add customer'));
    await tester.pumpAndSettle();

    // Back in the deal form with Anna picked; enter a value and save.
    final dealDialog = find.ancestor(
      of: find.text('Add deal'),
      matching: find.byType(AlertDialog),
    );
    await tester.enterText(
      find
          .descendant(of: dealDialog, matching: find.byType(TextFormField))
          .last,
      '2900',
    );
    await tester.tap(find.text('Add deal'));
    await tester.pumpAndSettle();

    final anna = store.privateCustomers.single;
    expect(anna.name, 'Anna Keller');
    expect(anna.phone, '+41 79 123 45 67');
    final deal = store.dealsFor(anna.id).single;
    // No products: named after the day.
    expect(deal.title, 'Deal of Nov 23, 2026');
    expect(deal.value, 2900);
  });

  testWidgets('the Dealers page lists private customers separately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await loadStore();
    store.addContact(name: 'Anna Keller', kind: ContactKind.person);
    await tester.pumpWidget(MolenstraatApp(store: store));

    await tester.tap(find.text('Dealers').first);
    await tester.pumpAndSettle();
    expect(find.text('Anna Keller'), findsNothing);

    await tester.tap(find.text('Private (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Private customers'), findsOneWidget);
    expect(find.text('Anna Keller'), findsOneWidget);
    expect(find.text('Alpenrad Velos'), findsNothing);
  });
}
