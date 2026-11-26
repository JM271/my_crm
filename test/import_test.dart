import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_crm/src/contact_import.dart';
import 'package:my_crm/src/crm_store.dart';
import 'package:my_crm/src/models.dart';

List<int> bytes(String s) => utf8.encode(s);

void main() {
  group('parseCsv', () {
    test('handles quotes, escaped quotes and newlines in fields', () {
      final rows = parseCsv('a,b\n"x, y","say ""hi""\nthere"\n');
      expect(rows, [
        ['a', 'b'],
        ['x, y', 'say "hi"\nthere'],
      ]);
    });

    test('detects semicolons and strips a BOM', () {
      final rows = parseCsv('﻿Name;Email\r\nAna;ana@x.ch\r\n');
      expect(rows, [
        ['Name', 'Email'],
        ['Ana', 'ana@x.ch'],
      ]);
    });
  });

  group('contactsFromCsv', () {
    test('reads a HubSpot companies export', () {
      final drafts = contactsFromCsv(
        bytes(
          'Company name,City,Postal Code,Phone Number,Website URL,Lifecycle Stage,Create Date\n'
          'Velo Muster AG,Bern,3000,031 123 45 67,https://www.velo-muster.ch/,lead,2026-03-09T08:42:45.899Z\n'
          'Trotti Shop,Sion,,,trotti-shop.ch,opportunity,\n'
          'Garage Beispiel,,,,,customer,\n',
        ),
      );
      expect(drafts, hasLength(3));
      expect(drafts[0].name, 'Velo Muster AG');
      expect(drafts[0].city, 'Bern');
      expect(drafts[0].phone, '031 123 45 67');
      expect(drafts[0].website, 'https://www.velo-muster.ch/');
      expect(drafts[0].type, ShopType.ebike);
      expect(drafts[0].createdAt, DateTime.utc(2026, 3, 9, 8, 42, 45, 899));
      expect(drafts[1].type, ShopType.trottinette);
      expect(drafts[1].status, ContactStatus.lead);
      // No keyword → type stays unknown instead of being guessed.
      expect(drafts[2].type, ShopType.unknown);
      expect(drafts[2].status, ContactStatus.klant);
    });

    test(
      'reads a HubSpot contacts export: company = shop, person = contact',
      () {
        final drafts = contactsFromCsv(
          bytes(
            'First Name,Last Name,Email,Company Name,Lifecycle Stage\n'
            'Anna,Muster,anna@roller.ch,Roller & Velo Muster,lead\n'
            ',,only@example.com,,subscriber\n',
          ),
        );
        expect(drafts[0].name, 'Roller & Velo Muster');
        expect(drafts[0].contactPerson, 'Anna Muster');
        expect(drafts[0].type, ShopType.both);
        expect(drafts[1].name, 'only@example.com');
        expect(drafts[1].contactPerson, '');
        expect(drafts[1].status, ContactStatus.lead);
      },
    );

    test('an explicit type column wins over guessing', () {
      final drafts = contactsFromCsv(
        bytes('Name;Type\nBike World;Trottinette shop\n'),
      );
      expect(drafts.single.type, ShopType.trottinette);
    });

    test('rejects files without name or email columns', () {
      expect(
        () => contactsFromCsv(bytes('foo,bar\n1,2\n')),
        throwsA(isA<CsvImportException>()),
      );
    });
  });

  group('ShopType.guess', () {
    test('uses clear keywords only', () {
      expect(ShopType.guess('Escootershop.ch', ''), ShopType.trottinette);
      expect(ShopType.guess('Salvadori Cicli', ''), ShopType.ebike);
      expect(ShopType.guess('Zweirad Center', ''), ShopType.ebike);
      expect(ShopType.guess('Lira Velo & Roller', ''), ShopType.both);
      expect(ShopType.guess('Moto Maniak', ''), ShopType.unknown);
      expect(ShopType.guess('Mobilec', 'www.mobilec.ch'), ShopType.unknown);
    });
  });

  group('CrmStore.importContacts', () {
    Future<CrmStore> store() async {
      final s = CrmStore(
        storage: MemoryStorage(),
        clock: () => DateTime(2026, 11, 23, 9),
      );
      await s.load();
      return s;
    }

    test('adds new dealers and does not duplicate existing ones', () async {
      final s = await store();
      final before = s.contacts.length;
      final drafts = [
        const ContactDraft(name: 'Velo Neu', city: 'Chur'),
        // Same shop name as a demo dealer (different case).
        const ContactDraft(name: 'rheinrad basel', city: 'Basel', phone: '000'),
      ];

      expect(s.previewImport(drafts), (added: 1, updated: 1));
      final result = s.importContacts(drafts, source: 'HubSpot');

      expect(result, (added: 1, updated: 1));
      expect(s.contacts.length, before + 1);
      // Existing data is kept, not overwritten.
      final rhein = s.contactById('c-rhein')!;
      expect(rhein.name, 'Rheinrad Basel');
      expect(rhein.phone, '+41 61 555 04 40');
      expect(s.activities.first.message, 'imported 1 new dealers from HubSpot');
    });

    test('branches sharing one email stay separate', () async {
      final s = await store();
      final before = s.contacts.length;
      s.importContacts([
        const ContactDraft(name: 'E-Hilf Olten', email: 'info@ehilf.ch'),
        const ContactDraft(name: 'E-Hilf Basel', email: 'info@ehilf.ch'),
      ]);
      expect(s.contacts.length, before + 2);
    });

    test('email-only entries are matched by email', () async {
      final s = await store();
      s.importContacts([
        const ContactDraft(name: 'shop@example.ch', email: 'shop@example.ch'),
      ]);
      final before = s.contacts.length;
      s.importContacts([
        const ContactDraft(name: 'Shop Example', email: 'SHOP@example.ch'),
      ]);
      expect(s.contacts.length, before);
      expect(s.contacts.any((c) => c.name == 'Shop Example'), isTrue);
    });

    test('branches on the same website stay separate', () async {
      final s = await store();
      final before = s.contacts.length;
      s.importContacts([
        const ContactDraft(name: 'Etrix Bern', website: 'etrix.ch'),
        const ContactDraft(name: 'Etrix Regensdorf', website: 'etrix.ch'),
      ]);
      expect(s.contacts.length, before + 2);
    });

    test('fills empty fields on re-import', () async {
      final s = await store();
      s.importContacts([const ContactDraft(name: 'Velo X')]);
      s.importContacts([
        const ContactDraft(
          name: 'Velo X',
          city: 'Thun',
          phone: '033',
          website: 'velo-x.ch',
          type: ShopType.ebike,
        ),
      ]);
      final x = s.contacts.firstWhere((c) => c.name == 'Velo X');
      expect(x.city, 'Thun');
      expect(x.phone, '033');
      expect(x.websiteLabel, 'velo-x.ch');
      expect(x.type, ShopType.ebike);
    });

    test('keeps the original creation date', () async {
      final s = await store();
      s.importContacts([
        ContactDraft(
          name: 'Old Shop',
          email: 'old@example.com',
          createdAt: DateTime.utc(2026, 2, 10, 12),
        ),
      ]);
      final old = s.contacts.firstWhere((c) => c.email == 'old@example.com');
      expect(old.createdAt, DateTime.utc(2026, 2, 10, 12).toLocal());
      // Newest first: the old import sits at the end.
      expect(s.contacts.last.email, 'old@example.com');
    });
  });

  test('HubSpot stages map to Lead, Customer and Partner', () {
    expect(statusFromLifecycle('lead'), ContactStatus.lead);
    expect(statusFromLifecycle('subscriber'), ContactStatus.lead);
    expect(statusFromLifecycle('customer'), ContactStatus.klant);
    expect(statusFromLifecycle('Partner'), ContactStatus.partner);
    expect(statusFromLifecycle('Dépôt-vente'), ContactStatus.depotVente);
    expect(statusFromLifecycle('depot vente'), ContactStatus.depotVente);
  });
}
