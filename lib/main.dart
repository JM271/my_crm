import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/cloud_app.dart';
import 'src/crm_store.dart';
import 'src/shell.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    // Online database: sign in, then load from Cloud Firestore.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const CloudApp());
    return;
  }
  // Not configured: keep everything in this browser / on this device.
  final store = CrmStore(storage: SharedPrefsStorage());
  await store.load();
  runApp(MolenstraatApp(store: store));
}

class MolenstraatApp extends StatelessWidget {
  const MolenstraatApp({super.key, required this.store, this.onFirstOpen});

  final CrmStore store;

  /// Called once after the CRM first appears (e.g. to offer a data upload).
  final Future<void> Function(BuildContext context)? onFirstOpen;

  @override
  Widget build(BuildContext context) {
    // The scope sits above MaterialApp so pushed routes (dealer details,
    // dialogs) can reach the store too.
    return CrmScope(
      store: store,
      child: MaterialApp(
        title: 'Molenstraat CRM',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: CrmShell(onFirstOpen: onFirstOpen),
      ),
    );
  }
}
