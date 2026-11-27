import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/main.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/models.dart';

DateTime fixedNow() => DateTime(2026, 11, 23, 9);

Future<CrmStore> loadStore([MemoryStorage? storage]) async {
  final store = CrmStore(storage: storage ?? MemoryStorage(), clock: fixedNow);
  await store.load();
  return store;
}

void main() {
  group('partner margins', () {
    test('partner price is retail minus the margin, in whole francs', () {
      expect(partnerPrice(2690, 20), 2152);
      expect(partnerPrice(2490, 25), 1868);
      expect(partnerPrice(2690, 0), 2690);
      expect(partnerPrice(2499, 33.3), 1667);
      expect(formatMargin(20), '20%');
      expect(formatMargin(22.5), '22.5%');
    });

    test('rates are only stored when set, and survive a reload', () async {
      final storage = MemoryStorage();
      final store = await loadStore(storage);
      final plain = store.addContact(name: 'Velo Plain');
      final partner = store.addContact(
        name: 'Velo Partner',
        depotMargin: 25,
        stockMargin: 32.5,
      );

      expect(plain.toJson().containsKey('depotMargin'), isFalse);
      expect(plain.toJson().containsKey('stockMargin'), isFalse);
      expect(plain.effectiveDepotMargin, Contact.defaultDepotMargin);
      expect(plain.effectiveStockMargin, 0);

      await Future<void>.delayed(Duration.zero);
      final reloaded = await loadStore(storage);
      final back = reloaded.contactById(partner.id)!;
      expect(back.depotMargin, 25);
      expect(back.stockMargin, 32.5);

      // Clearing a rate goes back to the standard.
      final cleared = back.copyWith(depotMargin: () => null);
      expect(cleared.depotMargin, isNull);
      expect(cleared.stockMargin, 32.5);
      expect(cleared.effectiveDepotMargin, 20);
    });

    test('private customers never get a margin', () async {
      final store = await loadStore();
      final anna = store.addContact(
        name: 'Anna Keller',
        kind: ContactKind.person,
        stockMargin: 30,
      );
      expect(anna.effectiveStockMargin, 0);
      expect(anna.effectiveDepotMargin, 0);
    });

    test('moving a bike can set its price at the new dealer', () async {
      final store = await loadStore();
      final bike = store.bikesAtDealers.first;
      final to = store.contacts.firstWhere((c) => c.id != bike.contactId);

      store.moveBike(bike.id, to.id, price: 1999);

      final moved = store.bikeById(bike.id)!;
      expect(moved.contactId, to.id);
      expect(moved.price, 1999);
      expect(moved.history.last.text, contains('price CHF 1,999'));
    });
  });

  group('forms', () {
    Future<CrmStore> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await loadStore();
      await tester.pumpWidget(MolenstraatApp(store: store));
      return store;
    }

    Finder dropdownField(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is DropdownMenu),
      ),
      matching: find.byType(TextField),
    );

    testWidgets('the dealer form saves both rates', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('New dealer').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Shop name'),
        'Velo Noor',
      );
      final depot = find.widgetWithText(TextFormField, 'Dépôt-vente margin %');
      await tester.enterText(depot, '150');
      await tester.tap(find.text('Add dealer'));
      await tester.pump();
      expect(find.text('Between 0 and 99'), findsOneWidget);

      await tester.enterText(depot, '22,5');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Own stock margin %'),
        '30%',
      );
      await tester.tap(find.text('Add dealer'));
      await tester.pumpAndSettle();

      final noor = store.contacts.firstWhere((c) => c.name == 'Velo Noor');
      expect(noor.depotMargin, 22.5);
      expect(noor.stockMargin, 30);
    });

    testWidgets('a deal for a partner uses their own stock margin', (
      tester,
    ) async {
      final store = await pump(tester);
      final alpen = store.contactById('c-alpen')!;
      store.updateContact(alpen.copyWith(stockMargin: () => 30));

      await tester.tap(find.text('Deals').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New deal').first);
      await tester.pumpAndSettle();

      await tester.enterText(dropdownField('Customer'), 'Alpen');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpenrad Velos · Thun').last);
      await tester.pumpAndSettle();
      await tester.enterText(dropdownField('Add product'), 'EF-26');
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-Fatbike 26″ · EF-26').last);
      await tester.pumpAndSettle();

      // Retail 2,500 minus 30%.
      expect(find.text('CHF 1,750'), findsOneWidget);
      expect(find.textContaining('retail minus 30%'), findsOneWidget);

      // A new private customer pays retail.
      await tester.enterText(dropdownField('Customer'), 'Marc Dubois');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '2,500'), findsOneWidget);

      // Back to the partner: their price again.
      await tester.enterText(dropdownField('Customer'), 'Alpenrad Velos');
      await tester.pumpAndSettle();
      expect(find.text('CHF 1,750'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add deal'));
      await tester.pumpAndSettle();
      final deal = store
          .dealsFor('c-alpen')
          .firstWhere((d) => d.createdAt == fixedNow());
      expect(deal.items.single.unitPrice, 1750);
    });

    testWidgets('bikes placed at a dealer use their dépôt-vente margin', (
      tester,
    ) async {
      final store = await pump(tester);
      final lago = store.contactById('c-lago')!;
      store.updateContact(lago.copyWith(depotMargin: () => 25));

      await tester.tap(find.text('Consignment').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place bikes'));
      await tester.pumpAndSettle();
      // One Mooi first at the standard 20%...
      await tester.tap(find.byKey(const Key('add-Mooi')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '2,152'), findsOneWidget);

      // ...then the dealer with 25%: the price follows.
      await tester.enterText(dropdownField('Dealer'), 'Lago');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lago Scooters Lugano · Lugano').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('their 25% margin'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Frame number'),
        'LG-200',
      );
      await tester.tap(find.text('Place bike'));
      await tester.pumpAndSettle();

      final placed = store.bikesAt('c-lago').single;
      // Retail 2,690 minus 25%, in whole francs.
      expect(placed.price, 2018);
    });
  });
}
