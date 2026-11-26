import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/main.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/models.dart';

/// Monday 23 Nov 2026, 09:00 — a fixed "now" so greetings/dates are stable.
DateTime fixedNow() => DateTime(2026, 11, 23, 9);

Future<CrmStore> loadStore([MemoryStorage? storage]) async {
  final store = CrmStore(storage: storage ?? MemoryStorage(), clock: fixedNow);
  await store.load();
  return store;
}

Future<CrmStore> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = await loadStore();
  await tester.pumpWidget(MolenstraatApp(store: store));
  return store;
}

void main() {
  testWidgets('shows the Molenstraat CRM dashboard with live numbers', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Good morning, Jonas 👋'), findsOneWidget);
    expect(find.text('Sales pipeline'), findsOneWidget);
    expect(find.text('Alpenrad Velos'), findsWidgets);
    // Open deals in demo data: 7,500 + 12,400 + 4,900.
    expect(find.text('CHF 24,800'), findsWidgets);
  });

  testWidgets('adds a dealer and displays it in the dealer list', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New dealer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Velo Noor');
    await tester.enterText(find.byType(TextFormField).at(4), 'Bern');
    await tester.tap(find.text('Add dealer'));
    await tester.pumpAndSettle();

    expect(find.text('Velo Noor'), findsOneWidget);
    expect(find.text('Bern'), findsOneWidget);
    expect(find.text('Velo Noor was added to your dealers.'), findsOneWidget);
  });

  testWidgets('dealer form requires a shop name and a valid e-mail', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New dealer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(6), 'not-an-email');
    await tester.tap(find.text('Add dealer'));
    await tester.pump();

    expect(find.text('Please enter a shop name'), findsOneWidget);
    expect(find.text('This email address is not valid'), findsOneWidget);
  });

  testWidgets('search filters dealers by city', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Dealers').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('contact-search')), 'basel');
    await tester.pumpAndSettle();

    expect(find.text('Rheinrad Basel'), findsOneWidget);
    expect(find.text('Lago Scooters Lugano'), findsNothing);
  });

  testWidgets('opens a dealer and deletes it', (tester) async {
    final store = await pumpApp(tester);

    await tester.tap(find.text('Dealers').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lago Scooters Lugano'));
    await tester.tap(find.text('Lago Scooters Lugano'));
    await tester.pumpAndSettle();
    expect(find.text('Marco Bernasconi'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(store.contactById('c-lago'), isNull);
    expect(find.text('Lago Scooters Lugano'), findsNothing);
  });

  testWidgets('every page renders on a phone-sized screen', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));

    for (final label in ['Dealers', 'Deals', 'Depot', 'Tasks', 'Reports']) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    expect(find.text('Top customers'), findsOneWidget);
  });

  testWidgets('the dealer list shows full names on a phone', (tester) async {
    final store = await pumpApp(tester, size: const Size(412, 915));
    const longName = 'Atelier Vélo & Trottinettes Électriques Genève-Carouge';
    store.addContact(name: longName, city: 'Carouge', phone: '022 123 45 67');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Dealers'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(longName));
    await tester.pumpAndSettle();

    final name = tester.renderObject<RenderParagraph>(find.text(longName));
    expect(name.didExceedMaxLines, isFalse);
    expect(name.size.height, greaterThan(20), reason: 'wraps, not cut off');
    expect(find.text('022 123 45 67'), findsOneWidget);
    store.logInteraction(
      contactId: store.contacts.firstWhere((c) => c.name == longName).id,
      kind: ActivityKind.call,
      note: 'Called',
    );
    await tester.pumpAndSettle();
    expect(find.text('022 123 45 67 · Last contact Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every page renders on a desktop screen', (tester) async {
    await pumpApp(tester);

    for (final label in [
      'Dealers',
      'Deals',
      'Consignment',
      'Tasks',
      'Reports',
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Top customers'), findsOneWidget);

    await tester.tap(find.text('Deals').first);
    await tester.pumpAndSettle();
    expect(find.text('Lost deals (1)'), findsOneWidget);
  });

  group('CrmStore', () {
    test('winning a deal makes the dealer a customer and logs it', () async {
      final store = await loadStore();
      expect(store.contactById('c-alpen')!.status, ContactStatus.lead);

      store.moveDeal('d-1', DealStage.gewonnen);

      expect(store.contactById('c-alpen')!.status, ContactStatus.klant);
      expect(store.activities.first.message, contains('awarded'));
      expect(store.dealsFor('c-alpen').single.closedAt, fixedNow());
    });

    test('deals are named after what is on them', () {
      DealItem item(String name, int qty) =>
          DealItem(name: name, quantity: qty, unitPrice: 1);
      final day = DateTime(2026, 11, 24);
      expect(dealTitleFor([], day), 'Deal of Nov 24, 2026');
      expect(
        dealTitleFor([item('Mooi', 2), item('Storm', 1), item('Mooi', 1)], day),
        '3 × Mooi, Storm',
      );
      expect(
        dealTitleFor([
          item('A', 1),
          item('B', 1),
          item('C', 1),
          item('D', 1),
        ], day),
        'A, B + 2 more',
      );
    });

    test('a new dealer starts as a lead', () async {
      final store = await loadStore();
      final c = store.addContact(name: 'Iris');
      expect(c.status, ContactStatus.lead);
    });

    test('a won deal leaves a partner a partner', () async {
      final store = await loadStore();
      final c = store.addContact(name: 'Iris', status: ContactStatus.partner);

      store.addDeal(
        contactId: c.id,
        title: 'Spring order',
        value: 5000,
        stage: DealStage.gewonnen,
      );

      expect(store.contactById(c.id)!.status, ContactStatus.partner);
    });

    test('the old "New" status loads as Lead', () {
      final c = Contact.fromJson({
        'id': 'c-old',
        'name': 'Velo Alt',
        'status': 'nieuw',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(c.status, ContactStatus.lead);
    });

    test('stats are computed from the data', () async {
      final store = await loadStore();
      expect(store.openPipelineValue, 24800);
      expect(store.wonValue, 24000 + 1850);
      expect(store.conversionRate, closeTo(2 / 3, 1e-9));
      // Two open tasks today (one of the three is already done).
      expect(store.urgentTaskCount, 2);
    });

    test('deleting a dealer removes its deals and tasks', () async {
      final store = await loadStore();
      store.deleteContact('c-seeland');
      expect(store.deals.where((d) => d.contactId == 'c-seeland'), isEmpty);
      expect(store.tasks.where((t) => t.contactId == 'c-seeland'), isEmpty);
    });

    test('data survives a reload', () async {
      final storage = MemoryStorage();
      final store = await loadStore(storage);
      store.addContact(name: 'Velo Noor', city: 'Bern');
      store.toggleTask('t-1', true);
      await Future<void>.delayed(Duration.zero);

      final reloaded = await loadStore(storage);
      expect(reloaded.contacts.first.name, 'Velo Noor');
      expect(reloaded.contacts.first.city, 'Bern');
      expect(reloaded.tasks.firstWhere((t) => t.id == 't-1').done, isTrue);
      expect(jsonDecode(storage.data!), contains('deals'));
    });
  });
}
