// Firebase configuration for the Molenstraat CRM.
//
// The CRM shares the Firebase project "inventory-molenstraat" with the
// Inventory and Offers apps (same accounts, same approval). It connects from
// the Android and iPhone apps and from the web app at
// https://crm-molenstraat.web.app ("Molenstraat CRM Web" in Firebase).
// The macOS build is for development and keeps demo data locally.
//
// These values are public app identifiers, not secrets: the data is
// protected by sign-in and the Firestore rules in the Inventory repository.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  /// Whether this build connects to the online database.
  static bool get isConfigured =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    _ when kIsWeb => web,
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => throw UnsupportedError(
      'The CRM database is only available on web, Android and iPhone.',
    ),
  };

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDMeZr_ehiP_q4RJYrLz80DO8JHMhIG_es',
    appId: '1:39036121879:web:25042373aeb3ed07cdfd52',
    messagingSenderId: '39036121879',
    projectId: 'inventory-molenstraat',
    authDomain: 'inventory-molenstraat.firebaseapp.com',
    storageBucket: 'inventory-molenstraat.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDOE6hBSQf9lskBUdVy814bNfA6v1JinNg',
    appId: '1:39036121879:android:654765b1f389bc9ccdfd52',
    messagingSenderId: '39036121879',
    projectId: 'inventory-molenstraat',
    storageBucket: 'inventory-molenstraat.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDHUly3YslgkQNReIVlRXqmcOIQq3SFYsY',
    appId: '1:39036121879:ios:650d6aa4a15b420fcdfd52',
    messagingSenderId: '39036121879',
    projectId: 'inventory-molenstraat',
    storageBucket: 'inventory-molenstraat.firebasestorage.app',
    iosBundleId: 'ch.molenstraat.crm',
  );
}
