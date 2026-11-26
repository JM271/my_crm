# Molenstraat CRM

A small Flutter CRM for Molenstraat to manage its e-bike and trottinette dealers and private customers.
Runs on Android and on the web at **https://crm-molenstraat.web.app**.

## Features

- **Overview:** live stats, sales pipeline, recent activity, today's tasks
- **Dealers:** shops with type (e-bikes / trottinettes / both), status (Lead / Customer / Partner / Dépôt-vente),
  contact person, city, phone, email and website.
  Search, filter by type and status, add/edit/delete, and a detail page with clickable phone/email/website,
  notes, deals, tasks and a timeline.
- **Import (CSV):** HubSpot *companies* export (each company becomes a dealer) or *contacts* export
  (company becomes the dealer, the person its contact person). Dealers are matched by email or shop name,
  so re-importing never creates duplicates and never overwrites edits made in the app.
- **Private customers:** people buying directly. Add one from the Dealers page (toggle *Private*) or straight
  from the *New deal* form. They have deals, tasks and a timeline, but stay out of dealer lists, stats,
  imports, exports and consignment. Stored as contacts with `kind: person`.
- **Activity log:** log calls, visits, emails and notes per dealer. The app tracks the last contact date,
  sorts dealers by "longest since contact" and lists leads/customers without contact for 30+ days on the dashboard.
- **Products:** catalog of models with dealer prices (avatar menu → Products). Deals can have order lines
  (quantity × price); the deal value is calculated from them.
- **Deals:** pipeline board per stage; move a deal through New → In talks → Proposal → Won/Lost.
  Winning a deal automatically makes the dealer a *Customer*.
- **Consignment (dépôt-vente):** bikes placed at dealers, tracked by frame number and model.
  Place several bikes at once (one frame number per line), mark as sold (with paid / not paid), returned,
  or move to another dealer; every bike keeps a history. Search by frame number, filter by status or dealer,
  see value at dealers and amounts still owed, export as CSV. Dealers holding bikes can't be deleted.
- **Tasks:** to-dos with due date/time, optionally linked to a dealer, grouped as Overdue / Today / Upcoming / Completed
- **Reports:** dealers per status and type, top cities, value per stage, products sold, top customers, task progress

- **Settings:** your name and currency (CHF or EUR).
- **Export & backup:** export dealers as CSV (re-importable, opens in Excel), save a full JSON backup and restore it.

The CRM is an **Android app** (tested on a Pixel 8a) and a **web app** at https://crm-molenstraat.web.app.
Both sign in to the same online database. The macOS build is for development only and keeps demo
data locally on the Mac (`shared_preferences`), with no access to the online database.

## Run

```sh
flutter pub get
flutter devices                     # phone connected by USB, or an emulator
flutter run -d <device-id>          # debug build on the phone
flutter build apk --release         # Android: build/app/outputs/flutter-apk/app-release.apk
flutter test
```

**Web app:** build and publish with

```sh
flutter build web --release
firebase deploy --only hosting --project inventory-molenstraat
```

`firebase.json` only describes the hosting site `crm-molenstraat`, so this never touches the
Inventory site (`inventory-molenstraat.web.app`) or the shared Firestore rules.

- **App ID:** `ch.molenstraat.crm`.
- **Install on the phone** (USB debugging on): `flutter build apk --release` then
  `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
  If the phone has a debug build from `flutter run` (signed with the debug key), Android refuses
  the release APK (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`): keep using `flutter run`, or uninstall
  the app once first, which signs you out on the phone.
- **Signing:** release builds are signed with `~/.molenstraat-keys/molenstraat-crm.jks`. Its
  passwords are in `android/key.properties`, which is git-ignored. Keep a copy of both somewhere
  safe: updates must be signed with the same key, or the app has to be uninstalled and reinstalled.
  Without key.properties the build falls back to the debug key.
- **Backups:** Android backups are turned off for this app (`allowBackup="false"`), so dealer data
  cached on the phone never ends up in device or Google backups.
- **Dev aid:** `--dart-define=START_PAGE=2` opens a specific page (0–5) on launch.

## Online database

The CRM shares the Firebase project **inventory-molenstraat** with the Inventory and Offers
apps: the same accounts, and the same approval.

- **Sign-in:** email + password in the mobile and web app, using the same account as Inventory. A new account sees
  "Waiting for approval" until an admin approves it in the Inventory app
  (account icon → Manage users, role Mitarbeiter/Admin).
- **Data:** stored under `workshops/molenstraat/`, one document per record, in `crmContacts`,
  `crmDeals`, `crmTasks`, `crmActivities`, `crmProducts` and `crmBikes`. Shared settings are in
  `crmConfig/settings`, and each person's display name is in `crmProfiles/{uid}`. Changes
  appear live for everyone signed in.
- **Security rules:** these live **only** in the Inventory repository (`Inventory/firestore.rules`,
  section "Molenstraat CRM"), with tests in `Inventory/tool/firebase_rules` (`npm test`, needs Java 21+).
  Publish them from there with `firebase deploy --only firestore:rules`. This project has no
  rules file on purpose: publishing one from here would replace the rules of all three apps.
- **First data:** on the phone, use avatar menu → Restore a backup and pick
  `imports/molenstraat-crm-hubspot-2026-11-23.json` (copy it to the phone first).
- **Firebase apps:** "Molenstraat CRM Android", "Molenstraat CRM Web" (hosting site `crm-molenstraat`)
  and an unused "Molenstraat CRM iOS" in project inventory-molenstraat.

## Structure

```
lib/
  main.dart                 app entry, loads the store
  src/
    models.dart             Contact (dealer), ShopType, Deal, Task, Activity
    contact_import.dart     CSV parsing + HubSpot column mapping
    crm_store.dart          state + persistence + stats (CrmStore, CrmScope)
    shell.dart              navigation, top bar, search
    theme.dart / format.dart
    pages/                  dashboard, contacts, contact detail, deals, tasks, reports
    widgets/                shared panels, rows and form dialogs
```

CSV files with real dealer data go in `imports/`, which is git-ignored.
