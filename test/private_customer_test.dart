import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/main.dart';
import 'package:my_crm/src/contact_import.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/models.dart';
import 'package:my_crm/src/widgets/forms.dart';

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

  testWidgets('a new name typed into a new deal is saved as a customer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await loadStore();
    final contacts = store.allContacts.length;
    await tester.pumpWidget(MolenstraatApp(store: store));

    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New deal').first);
    await tester.pumpAndSettle();

    final dealDialog = find.ancestor(
      of: find.text('Add deal'),
      matching: find.byType(AlertDialog),
    );
    final customerField = find.descendant(
      of: find.byType(DealerPicker),
      matching: find.byType(TextField),
    );
    await tester.enterText(customerField, 'Marc Dubois');
    await tester.pumpAndSettle();
    expect(find.textContaining('is not in the CRM yet'), findsOneWidget);

    await tester.enterText(
      find
          .descendant(of: dealDialog, matching: find.byType(TextFormField))
          .last,
      '1800',
    );
    await tester.tap(find.text('Add deal'));
    await tester.pumpAndSettle();

    expect(find.text('Add deal'), findsNothing);
    expect(store.allContacts.length, contacts + 1);
    final marc = store.privateCustomers.single;
    expect(marc.name, 'Marc Dubois');
    expect(store.dealsFor(marc.id).single.value, 1800);
  });

  testWidgets('typing the name of an existing customer picks them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await loadStore();
    final anna = store.addContact(
      name: 'Anna Keller',
      kind: ContactKind.person,
    );
    final contacts = store.allContacts.length;
    await tester.pumpWidget(MolenstraatApp(store: store));

    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New deal').first);
    await tester.pumpAndSettle();

    final dealDialog = find.ancestor(
      of: find.text('Add deal'),
      matching: find.byType(AlertDialog),
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(DealerPicker),
        matching: find.byType(TextField),
      ),
      'anna keller',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('is not in the CRM yet'), findsNothing);
    await tester.enterText(
      find
          .descendant(of: dealDialog, matching: find.byType(TextFormField))
          .last,
      '900',
    );
    await tester.tap(find.text('Add deal'));
    await tester.pumpAndSettle();

    expect(store.allContacts.length, contacts);
    expect(store.dealsFor(anna.id).single.value, 900);
  });

  group('a new task', () {
    Future<CrmStore> openNewTask(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await loadStore();
      await tester.pumpWidget(MolenstraatApp(store: store));
      await tester.tap(find.text('Tasks').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New task').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Task'),
        'Call back about the fatbike',
      );
      return store;
    }

    Finder customerField() => find.descendant(
      of: find.byType(DealerPicker),
      matching: find.byType(TextField),
    );

    Task savedTask(CrmStore store) => store.tasks.singleWhere(
      (t) => t.title == 'Call back about the fatbike',
    );

    testWidgets('saves a new name as a private customer', (tester) async {
      final store = await openNewTask(tester);
      final contacts = store.allContacts.length;

      await tester.enterText(customerField(), 'Lea Frei');
      await tester.pumpAndSettle();
      expect(find.textContaining('with this task'), findsOneWidget);
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();

      expect(find.text('Add task'), findsNothing);
      expect(store.allContacts.length, contacts + 1);
      final lea = store.privateCustomers.single;
      expect(lea.name, 'Lea Frei');
      expect(savedTask(store).contactId, lea.id);
    });

    testWidgets('can still be saved for nobody', (tester) async {
      final store = await openNewTask(tester);
      final contacts = store.allContacts.length;

      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(savedTask(store).contactId, isNull);

      expect(store.allContacts.length, contacts);
    });

    testWidgets('never saves "Nobody" as a customer', (tester) async {
      final store = await openNewTask(tester);
      final contacts = store.allContacts.length;

      await tester.enterText(customerField(), 'Nobody');
      await tester.pumpAndSettle();
      expect(find.textContaining('is not in the CRM yet'), findsNothing);
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();

      expect(store.allContacts.length, contacts);
      expect(savedTask(store).contactId, isNull);
    });
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
