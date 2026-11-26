import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/main.dart';
import 'package:my_crm/src/contact_import.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/format.dart';
import 'package:my_crm/src/models.dart';
import 'package:my_crm/src/pages/contacts_page.dart';

DateTime fixedNow() => DateTime(2026, 11, 23, 9);

Future<CrmStore> loadStore([MemoryStorage? storage]) async {
  final s = CrmStore(storage: storage ?? MemoryStorage(), clock: fixedNow);
  await s.load();
  return s;
}

void main() {
  group('settings', () {
    test('defaults to CHF and can switch to EUR; survives reload', () async {
      final storage = MemoryStorage();
      final s = await loadStore(storage);
      expect(s.currency, 'CHF');
      expect(formatMoney(24800), 'CHF 24,800');

      s.updateSettings(userName: 'Anna Muster', currency: 'EUR');
      expect(formatMoney(24800), '€24,800');
      await Future<void>.delayed(Duration.zero);

      final reloaded = await loadStore(storage);
      expect(reloaded.userName, 'Anna Muster');
      expect(reloaded.firstName, 'Anna');
      expect(reloaded.currency, 'EUR');
      reloaded.updateSettings(currency: 'CHF'); // reset global for other tests
    });

    test('parseMoney understands Swiss formats', () {
      expect(parseMoney("CHF 4'500"), 4500);
      expect(parseMoney('4,500.50'), 4500.5);
      expect(parseMoney('€2,490'), 2490);
      expect(parseMoney(''), isNull);
    });
  });

  group('backup', () {
    test('round-trips all data', () async {
      final a = await loadStore();
      a.addProduct(name: 'Test bike', price: 999);
      a.logInteraction(
        contactId: 'c-lago',
        kind: ActivityKind.visit,
        note: 'Shop visit',
      );
      final backup = a.exportBackup();

      final b = await loadStore();
      b.clearAll();
      b.restoreBackup(backup);
      expect(b.contacts.length, a.contacts.length);
      expect(b.deals.length, a.deals.length);
      expect(b.products.map((p) => p.name), contains('Test bike'));
      expect(b.lastContactAt('c-lago'), fixedNow());
      expect(b.deals.firstWhere((d) => d.id == 'd-1').items.single.quantity, 3);
    });

    test('rejects other files and leaves data untouched', () async {
      final s = await loadStore();
      final before = s.contacts.length;
      expect(() => s.restoreBackup('not json'), throwsFormatException);
      expect(
        () => s.restoreBackup(jsonEncode({'contacts': []})),
        throwsFormatException,
      );
      expect(s.contacts.length, before);
    });
  });

  test('dealer CSV export can be imported again', () async {
    final s = await loadStore();
    final csv = s.exportDealersCsv();
    final drafts = contactsFromCsv(utf8.encode(csv));
    expect(drafts.length, s.contacts.length);
    final alpen = drafts.firstWhere((d) => d.name == 'Alpenrad Velos');
    expect(alpen.type, ShopType.ebike);
    expect(alpen.city, 'Thun');
    expect(alpen.contactPerson, 'Martina Keller');
    expect(alpen.status, ContactStatus.lead);
    final rhein = drafts.firstWhere((d) => d.name == 'Rheinrad Basel');
    expect(rhein.type, ShopType.both);
    expect(rhein.status, ContactStatus.klant);
    // Re-importing into the same store creates no duplicates.
    expect(s.previewImport(drafts), (added: 0, updated: s.contacts.length));
  });

  group('order lines', () {
    test('deal value is the sum of its lines', () async {
      final s = await loadStore();
      final deal = s.addDeal(
        contactId: 'c-lago',
        title: 'Test order',
        value: 0,
        items: const [
          DealItem(name: 'E-Fatbike 26″', quantity: 2, unitPrice: 2500),
          DealItem(name: 'Accessory pack', quantity: 3, unitPrice: 185),
        ],
      );
      expect(deal.value, 5555);
      expect(deal.units, 5);
    });

    test('product sales come from won deals only', () async {
      final s = await loadStore();
      final sales = s.wonProductSales();
      // Demo: 10 E-Fatbikes won (d-4); the 3 in d-1 are only a proposal.
      final efat = sales.firstWhere((x) => x.name == 'E-Fatbike 26″');
      expect(efat.units, 10);
      expect(efat.revenue, 24000);
    });

    test('deleting a product keeps existing order lines', () async {
      final s = await loadStore();
      s.deleteProduct('p-efat26');
      expect(s.deals.firstWhere((d) => d.id == 'd-1').value, 7500);
    });
  });

  group('interactions', () {
    test('last contact is the latest logged call/visit/email/note', () async {
      final s = await loadStore();
      expect(s.lastContactAt('c-lago'), isNull);
      // Demo: email to Alpenrad 2 days ago.
      expect(s.lastContactAt('c-alpen'), DateTime(2026, 11, 21, 15));
      s.logInteraction(
        contactId: 'c-alpen',
        kind: ActivityKind.call,
        note: 'Called',
      );
      expect(s.lastContactAt('c-alpen'), fixedNow());
    });

    test('automatic activity never pushes out logged interactions', () async {
      final s = await loadStore();
      for (var i = 0; i < 300; i++) {
        s.addContact(name: 'Shop $i');
      }
      expect(
        s.activities.where((a) => a.isInteraction).length,
        3, // the demo call, visit and email
      );
    });

    test('follow-up sort puts never-contacted first, then oldest', () async {
      final s = await loadStore();
      final filter = ContactFilter(
        query: '',
        status: null,
        onStatusChanged: (_) {},
        sort: DealerSort.followUp,
      );
      final order = filter
          .apply(s.contacts, lastContact: s.lastContactAt)
          .map((c) => c.id)
          .toList();
      // Seeland and Lago were never contacted; Trotti 20d, Rhein 12d, Alpen 2d.
      expect(order.sublist(2), ['c-trotti', 'c-rhein', 'c-alpen']);
      expect(order.take(2).toSet(), {'c-seeland', 'c-lago'});
    });
  });

  group('consignment', () {
    test('places several bikes at once and finds them by frame', () async {
      final s = await loadStore();
      final placed = s.placeBikes(
        contactId: 'c-alpen',
        frameNumbers: ['ABC-001', ' abc 002 ', ''],
        model: 'E-Fatbike 26″',
        productId: 'p-efat26',
        price: 2500,
      );
      expect(placed.length, 2);
      expect(s.bikesAt('c-alpen').length, 2);
      // Lookup ignores case, spaces and dashes.
      expect(s.bikeByFrame('abc002')?.contactId, 'c-alpen');
      expect(
        s.activities.first.message,
        'received 2 × E-Fatbike 26″ on consignment',
      );
    });

    test('places a mix of models in one go', () async {
      final s = await loadStore();
      final placed = s.placeBikeBatch(
        contactId: 'c-alpen',
        bikes: [
          (frameNumber: 'M-1', model: 'Mooi', productId: null, price: 2690),
          (frameNumber: 'M-2', model: 'Mooi', productId: null, price: 2690),
          (frameNumber: 'B-1', model: 'Brommer', productId: null, price: 2490),
        ],
      );
      expect(placed.length, 3);
      expect(s.bikeByFrame('B-1')!.price, 2490);
      expect(
        s.activities.first.message,
        'received 3 bikes (2 × Mooi, 1 × Brommer) on consignment',
      );
    });

    test('the consignment models and their prices', () {
      expect(
        {for (final m in consignmentModels) m.name: m.price},
        {'Mooi': 2690, 'Brommer': 2490, 'Dapper Pro': 2490, 'Storm': 2690},
      );
    });

    test('rejects duplicate frame numbers and adds nothing', () async {
      final s = await loadStore();
      final before = s.bikes.length;
      expect(
        () => s.placeBikes(
          contactId: 'c-alpen',
          frameNumbers: ['NEW-1', 'msf26e 240311'], // exists in demo
          model: 'X',
        ),
        throwsArgumentError,
      );
      expect(
        () => s.placeBikes(
          contactId: 'c-alpen',
          frameNumbers: ['DUP-1', 'dup1'],
          model: 'X',
        ),
        throwsArgumentError,
      );
      expect(s.bikes.length, before);
    });

    test('sold → paid, returned and moved keep a history', () async {
      final s = await loadStore();
      expect(s.consignmentAmountOwed, 2500); // demo b-3 sold, unpaid
      s.setBikePaid('b-3', true);
      expect(s.consignmentAmountOwed, 0);

      s.markBikeSold('b-1', salePrice: 3290);
      expect(s.bikeById('b-1')!.awaitingPayment, isTrue);

      s.moveBike('b-2', 'c-alpen');
      final moved = s.bikeById('b-2')!;
      expect(moved.contactId, 'c-alpen');
      expect(
        moved.history.last.text,
        'Moved from Rheinrad Basel to Alpenrad Velos',
      );

      s.markBikeReturned('b-4');
      expect(s.bikeById('b-4')!.status, ConsignmentStatus.returned);
      // A returned bike can be placed again.
      s.moveBike('b-4', 'c-lago');
      expect(s.bikeById('b-4')!.isAtDealer, isTrue);
      expect(
        s.bikeById('b-4')!.history.last.text,
        'Placed at Lago Scooters Lugano',
      );
    });

    test('a dealer holding bikes cannot be deleted', () async {
      final s = await loadStore();
      expect(() => s.deleteContact('c-rhein'), throwsStateError);
      s.markBikeReturned('b-1');
      s.markBikeReturned('b-2');
      s.deleteContact('c-rhein');
      expect(s.bikes.where((b) => b.contactId == 'c-rhein'), isEmpty);
    });

    test('bikes survive backup/restore and appear in CSV export', () async {
      final a = await loadStore();
      final b = await loadStore();
      b.clearAll();
      b.restoreBackup(a.exportBackup());
      expect(b.bikes.length, a.bikes.length);
      expect(b.bikeById('b-3')!.salePrice, 3290);
      final csv = a.exportBikesCsv();
      expect(
        csv,
        contains('MSF26E-240311,E-Fatbike 26″,Rheinrad Basel,Basel,At dealer'),
      );
    });
  });

  group('screens', () {
    Future<CrmStore> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await loadStore();
      await tester.pumpWidget(MolenstraatApp(store: store));
      return store;
    }

    testWidgets('the place-bikes form fits a phone with all four models', (
      tester,
    ) async {
      // Pixel 8a: 1080 × 2400 px at 2.625 → about 411 × 914 dp.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final store = await loadStore();
      await tester.pumpWidget(MolenstraatApp(store: store));
      await tester.tap(find.text('Depot').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      for (final m in consignmentModels) {
        await tester.ensureVisible(find.byKey(Key('add-${m.name}')));
        await tester.tap(find.byKey(Key('add-${m.name}')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Place 4 bikes'), findsOneWidget);
      expect(find.text('CHF 10,360'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new deal on a phone: customer, product search, total', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final store = await loadStore();
      await tester.pumpWidget(MolenstraatApp(store: store));
      await tester.tap(find.text('Deals').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();

      // Full screen on a phone, steps in order.
      expect(find.byType(Dialog), findsOneWidget);
      // Who, what, how much: no name to type, no stage for a new deal.
      expect(find.text('WHO'), findsOneWidget);
      expect(find.text('WHAT'), findsOneWidget);
      expect(find.text('HOW MUCH'), findsOneWidget);
      expect(find.text('STAGE'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Description'), findsNothing);

      Finder field(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is DropdownMenu),
        ),
        matching: find.byType(TextField),
      );
      await tester.tap(field('Customer'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Customer'), 'Alpen');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpenrad Velos · Thun').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(field('Add product'));
      await tester.tap(field('Add product'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Add product'), 'EF-26');
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-Fatbike 26″ · EF-26').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('One more'));
      await tester.pumpAndSettle();
      expect(find.text('CHF 5,000'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Add deal'));
      await tester.pumpAndSettle();

      final deal = store.deals.firstWhere(
        (d) => d.title == '2 × E-Fatbike 26″',
      );
      expect(deal.contactId, 'c-alpen');
      expect(deal.items.single.quantity, 2);
      expect(deal.value, 5000);
      expect(deal.stage, DealStage.nieuw);
    });

    testWidgets('dashboard shows the follow-up card', (tester) async {
      await pump(tester);
      expect(find.text('Needs follow-up'), findsOneWidget);
      // Dealers silent for 30+ days: Lago (partner) and Seeland (lead), both
      // never contacted. TrottiCity (20d) and Rheinrad (12d) are recent.
      expect(
        find.text('2 dealers without contact in 30+ days'),
        findsOneWidget,
      );
      expect(find.text('No contact logged yet'), findsNWidgets(2));
    });

    testWidgets('logs a call from the dealer page', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('Dealers').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lago Scooters Lugano'));
      await tester.tap(find.text('Lago Scooters Lugano'));
      await tester.pumpAndSettle();
      expect(find.text('No contact logged yet'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log'));
      await tester.tap(find.widgetWithText(FilledButton, 'Log'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'Wants a demo bike',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.lastContactAt('c-lago'), fixedNow());
      expect(find.text('Wants a demo bike'), findsOneWidget);
      expect(find.text('Last contact: today'), findsOneWidget);
    });

    testWidgets('adds a product from the products page', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      expect(find.text('E-Fatbike 26″'), findsOneWidget);

      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Fatbike XL');
      await tester.enterText(find.byType(TextFormField).at(2), "3'190");
      await tester.tap(find.text('Add product'));
      await tester.pumpAndSettle();

      expect(store.products.last.price, 3190);
      expect(find.text('Fatbike XL'), findsOneWidget);
      expect(find.text('CHF 3,190'), findsOneWidget);
    });

    testWidgets('places bikes and finds one by frame number', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('Consignment').first);
      await tester.pumpAndSettle();
      expect(find.text('MSF26E-240311'), findsOneWidget);

      await tester.tap(find.text('Place bikes'));
      await tester.pumpAndSettle();
      // Pick the dealer by typing in the searchable field.
      final dealerField = find.descendant(
        of: find.byType(DropdownMenu<String?>),
        matching: find.byType(TextField),
      );
      await tester.tap(dealerField);
      await tester.pumpAndSettle();
      await tester.enterText(dealerField, 'Lago');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lago Scooters Lugano · Lugano').last);
      await tester.pumpAndSettle();
      // One Mooi and one Storm, each with its own frame number.
      await tester.tap(find.byKey(const Key('add-Mooi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-Storm')));
      await tester.pumpAndSettle();
      final frames = find.widgetWithText(TextFormField, 'Frame number');
      await tester.enterText(frames.at(0), 'LG-100');
      await tester.enterText(frames.at(1), 'lg 100');
      await tester.tap(find.text('Place 2 bikes'));
      await tester.pumpAndSettle();
      expect(find.text('Entered twice'), findsOneWidget);

      await tester.enterText(frames.at(1), 'LG-101');
      await tester.tap(find.text('Place 2 bikes'));
      await tester.pumpAndSettle();

      final placed = store.bikesAt('c-lago');
      expect(placed.length, 2);
      expect(placed.map((b) => b.model), containsAll(['Mooi', 'Storm']));
      expect(placed.every((b) => b.price == 2690), isTrue);
      expect(store.activities.first.message, contains('2 bikes'));
      await tester.enterText(find.byKey(const Key('frame-search')), 'lg101');
      await tester.pumpAndSettle();
      expect(find.text('LG-101'), findsOneWidget);
      expect(find.text('LG-100'), findsNothing);
    });

    testWidgets('settings change the name and currency', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Anna Muster');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(store.userName, 'Anna Muster');
      expect(find.text('Good morning, Anna 👋'), findsOneWidget);
    });
  });
}
