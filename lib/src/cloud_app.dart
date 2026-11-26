import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'crm_store.dart';
import 'firestore_storage.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Signs the user in, waits for their approval, then opens the CRM backed
/// by Cloud Firestore.
///
/// Accounts and approval are shared with the other Molenstraat apps
/// (Inventory, Offers): an account may open the data once an admin has
/// given it the role admin or editor in workshops/molenstraat/members.
class CloudApp extends StatelessWidget {
  const CloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Shell(child: _Loading());
        }
        final user = snap.data;
        if (user == null) return const _Shell(child: SignInPage());
        return _MembershipGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

/// Minimal MaterialApp for the screens shown before the CRM opens.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Molenstraat CRM',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: Scaffold(body: child),
  );
}

class _Loading extends StatelessWidget {
  const _Loading({this.message = 'Loading…'});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: forest),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: muted)),
      ],
    ),
  );
}

/// Centered card used by the sign-in screens.
class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Panel(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: forest,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.grass_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'molenstraat',
                    style: TextStyle(
                      color: ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

String _authError(Object e) {
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email or password is wrong.',
      'email-already-in-use' => 'An account with this email already exists.',
      'weak-password' => 'Choose a password with at least 6 characters.',
      'invalid-email' => 'This email address is not valid.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled in Firebase yet.',
      'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
      _ => e.message ?? e.code,
    };
  }
  return '$e';
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _authError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
    final auth = FirebaseAuth.instance;
    final email = _email.text.trim();
    if (_creating) {
      await auth.createUserWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
    } else {
      await auth.signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
    }
  });

  Future<void> _reset() => _run(() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      throw 'Enter your email first.';
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) setState(() => _info = 'Password reset email sent to $email.');
  });

  @override
  Widget build(BuildContext context) {
    return _AuthCard(
      children: [
        Text(
          _creating ? 'Create your account' : 'Sign in',
          style: const TextStyle(
            color: ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _creating
              ? 'An admin has to approve a new account before it can see '
                    'any data.'
              : 'Use the same account as for the Inventory and Offers apps.',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: inputDecoration('Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: inputDecoration('Password'),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: danger, fontSize: 13)),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: const TextStyle(color: forest, fontSize: 13)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: Text(_creating ? 'Create account' : 'Sign in'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _creating = !_creating;
                      _error = null;
                    }),
              child: Text(_creating ? 'I have an account' : 'Create account'),
            ),
            if (!_creating)
              TextButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Forgot password?'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Waits until the signed-in account is approved for the Molenstraat
/// workshop, then opens the CRM.
class _MembershipGate extends StatefulWidget {
  const _MembershipGate({super.key, required this.user});

  final User user;

  @override
  State<_MembershipGate> createState() => _MembershipGateState();
}

class _MembershipGateState extends State<_MembershipGate> {
  late final _db = FirebaseFirestore.instance;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _membership = _db
      .doc('workshops/molenstraat/members/${widget.user.uid}')
      .snapshots();

  @override
  void initState() {
    super.initState();
    // Lets admins find the account in the Inventory app's user list.
    final email = widget.user.email;
    if (email != null) {
      _db
          .doc('users/${widget.user.uid}')
          .set({'email': email})
          .catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _membership,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Shell(
            child: _Notice(
              title: 'Could not check your access',
              message: '${snap.error}',
            ),
          );
        }
        if (!snap.hasData) {
          return const _Shell(child: _Loading(message: 'Checking access…'));
        }
        final role = snap.data!.data()?['role'];
        if (role != 'admin' && role != 'editor') {
          return _Shell(
            child: _Notice(
              title: 'Waiting for approval',
              message:
                  '${widget.user.email} is signed in but not approved yet. '
                  'An admin can approve it in the Inventory app under '
                  'account icon → Manage users. This page opens the CRM '
                  'by itself once that is done.',
            ),
          );
        }
        return _SignedIn(
          key: ValueKey('${widget.user.uid}-$role'),
          user: widget.user,
        );
      },
    );
  }
}

/// A message card with a sign-out button.
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _AuthCard(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Text(message, style: const TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => FirebaseAuth.instance.signOut(),
        child: const Text('Sign out'),
      ),
    ],
  );
}

/// Loads the workspace for a signed-in user and opens the CRM.
class _SignedIn extends StatefulWidget {
  const _SignedIn({super.key, required this.user});

  final User user;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  CrmStore? _store;
  FirestoreStorage? _storage;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final storage = FirestoreStorage(
      db: FirebaseFirestore.instance,
      uid: widget.user.uid,
      email: widget.user.email ?? '',
    );
    final store = CrmStore(storage: storage)
      ..accountEmail = widget.user.email
      ..onSignOut = FirebaseAuth.instance.signOut;
    try {
      await store.load();
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _store = store;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      final denied =
          error is FirebaseException && error.code == 'permission-denied';
      return _Shell(
        child: _Notice(
          title: denied
              ? 'No access to the CRM data'
              : 'Could not open the CRM',
          message: denied
              ? 'Your account is approved, but the database does not allow '
                    'the CRM yet. Its rules need the CRM section '
                    '(see README → Online database).'
              : '$error',
        ),
      );
    }
    final store = _store;
    if (store == null) {
      return const _Shell(child: _Loading(message: 'Opening your CRM…'));
    }
    return MolenstraatApp(
      store: store,
      onFirstOpen: _storage!.wasEmpty ? _offerUpload : null,
    );
  }

  /// First sign-in on an empty database: offer to upload this browser's data.
  Future<void> _offerUpload(BuildContext context) async {
    final store = _store!;
    final local = await SharedPrefsStorage().load();
    Map<String, Object?>? localJson;
    if (local != null) {
      localJson = jsonDecode(local) as Map<String, Object?>;
      if (((localJson['contacts'] as List?) ?? const []).isEmpty) {
        localJson = null;
      }
    }
    if (!context.mounted) return;
    final dealers = ((localJson?['contacts'] as List?) ?? const []).length;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Your online database is empty',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          localJson != null
              ? 'This browser has $dealers dealers saved locally. Upload them '
                    '(with deals, tasks, bikes and products) to the online '
                    'database?'
              : 'Use "Restore a backup" in the avatar menu to load your '
                    'HubSpot import file, or start adding dealers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: Text(localJson != null ? 'Start empty' : 'OK'),
          ),
          if (localJson != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'upload'),
              child: const Text('Upload'),
            ),
        ],
      ),
    );
    if (choice == 'upload' && localJson != null) {
      // Keep the signed-in user's own name rather than the local one.
      final settings =
          (localJson['settings'] as Map?)?.cast<String, Object?>() ?? {};
      localJson['settings'] = {...settings, 'userName': store.userName};
      store.restoreBackup(jsonEncode(localJson));
      if (context.mounted) {
        showMessage(context, 'Uploaded ${store.contacts.length} dealers.');
      }
    }
  }
}
