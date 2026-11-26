import 'dart:convert';

import 'models.dart';

/// A dealer read from an import file, before it is added to the store.
class ContactDraft {
  const ContactDraft({
    required this.name,
    this.type = ShopType.unknown,
    this.contactPerson = '',
    this.street = '',
    this.postalCode = '',
    this.city = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.notes = '',
    this.status = ContactStatus.lead,
    this.createdAt,
  });

  /// Shop name.
  final String name;
  final ShopType type;
  final String contactPerson;
  final String street;
  final String postalCode;
  final String city;
  final String email;
  final String phone;
  final String website;
  final String notes;
  final ContactStatus status;
  final DateTime? createdAt;
}

/// Parses CSV text (RFC 4180: quoted fields, escaped quotes, newlines inside
/// quotes). Detects `;` as delimiter when that's what the header uses, which
/// is common for Excel exports in Europe.
List<List<String>> parseCsv(String input) {
  var text = input.startsWith('﻿') ? input.substring(1) : input;
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final firstLine = text.split('\n').first;
  final delimiter =
      ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ',';

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  // Drop blank lines.
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// Column names accepted per field: HubSpot export labels ("Company name"),
/// HubSpot internal names ("firstname"), and a few common alternatives.
const _columns = {
  // Shop name. HubSpot company exports use "Company name"/"Name"; contact
  // exports use "Company Name" for the person's company.
  'shop': ['companyname', 'company', 'name', 'shopname', 'dealer', 'naam'],
  'first': ['firstname', 'voornaam', 'vorname'],
  'last': ['lastname', 'achternaam', 'nachname', 'surname'],
  'person': ['fullname', 'contactname', 'contactperson'],
  'email': ['email', 'emailaddress', 'mail'],
  'phone': [
    'phonenumber',
    'phone',
    'mobilephone',
    'mobilephonenumber',
    'telephone',
    'telefoon',
    'telefon',
  ],
  'street': ['streetaddress', 'address', 'street', 'strasse', 'adresse'],
  'zip': ['postalcode', 'zip', 'zipcode', 'plz', 'npa', 'postcode'],
  'city': ['city', 'town', 'ort', 'stadt', 'ville', 'plaats'],
  'notes': ['notes', 'description', 'note', 'bemerkungen'],
  'website': ['websiteurl', 'website', 'companydomainname', 'domain', 'url'],
  'type': ['shoptype', 'type', 'category', 'industry'],
  'stage': ['lifecyclestage', 'status', 'leadstatus'],
  'created': ['createdate', 'createdon', 'createdat', 'datecreated'],
};

/// Maps HubSpot lifecycle stages (labels or internal values) to our statuses.
ContactStatus statusFromLifecycle(String value) {
  final v = _normalize(value);
  if (v.isEmpty) return ContactStatus.lead;
  if (['customer', 'evangelist', 'klant', 'kunde'].contains(v)) {
    return ContactStatus.klant;
  }
  if (['partner', 'reseller', 'haendler'].contains(v)) {
    return ContactStatus.partner;
  }
  // "Dépôt-vente" normalizes to "dptvente" (accents are dropped).
  if (['depotvente', 'dptvente', 'consignment', 'kommission'].contains(v)) {
    return ContactStatus.depotVente;
  }
  // lead, subscriber, marketingqualifiedlead, opportunity, other, …
  return ContactStatus.lead;
}

ShopType _typeFrom(String value) {
  final v = _normalize(value);
  final scooter = RegExp('trott|scoot|roller').hasMatch(v);
  final bike = RegExp('bike|velo|cycl').hasMatch(v);
  if (scooter && bike) return ShopType.both;
  if (scooter) return ShopType.trottinette;
  if (bike) return ShopType.ebike;
  return ShopType.unknown;
}

class CsvImportException implements Exception {
  const CsvImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads dealers from CSV bytes: a HubSpot companies export, a HubSpot
/// contacts export (the company becomes the shop and the person its contact
/// person), or any similar CSV.
List<ContactDraft> contactsFromCsv(List<int> bytes) {
  final rows = parseCsv(utf8.decode(bytes, allowMalformed: true));
  if (rows.isEmpty) throw const CsvImportException('The file is empty.');

  final header = rows.first.map(_normalize).toList();
  int? col(String key) {
    for (final name in _columns[key]!) {
      final i = header.indexOf(name);
      if (i >= 0) return i;
    }
    return null;
  }

  final shop = col('shop'), first = col('first'), last = col('last');
  final person = col('person'), email = col('email'), phone = col('phone');
  final city = col('city'), website = col('website'), type = col('type');
  final street = col('street'), zip = col('zip'), notes = col('notes');
  final stage = col('stage'), created = col('created');
  if ([shop, first, last, person, email].every((c) => c == null)) {
    throw const CsvImportException(
      'No name or email column found. Expected columns like '
      '"Company name", "City", "Phone Number" or "Email".',
    );
  }

  String cell(List<String> row, int? i) =>
      i == null || i >= row.length ? '' : row[i].trim();

  final drafts = <ContactDraft>[];
  for (final row in rows.skip(1)) {
    final mail = cell(row, email);
    var personName = [
      cell(row, first),
      cell(row, last),
    ].where((p) => p.isNotEmpty).join(' ');
    if (personName.isEmpty) personName = cell(row, person);
    final shopName = cell(row, shop);
    // No shop name: fall back to the person, then the email.
    final name = shopName.isNotEmpty
        ? shopName
        : (personName.isNotEmpty ? personName : mail);
    if (name.isEmpty) continue;
    final site = cell(row, website);
    final givenType = _typeFrom(cell(row, type));
    drafts.add(
      ContactDraft(
        name: name,
        contactPerson: shopName.isNotEmpty ? personName : '',
        street: cell(row, street),
        postalCode: cell(row, zip),
        city: cell(row, city),
        notes: cell(row, notes),
        email: mail,
        phone: cell(row, phone),
        website: site,
        type: givenType != ShopType.unknown
            ? givenType
            : ShopType.guess(name, site),
        status: statusFromLifecycle(cell(row, stage)),
        createdAt: DateTime.tryParse(cell(row, created)),
      ),
    );
  }
  return drafts;
}
