import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'data/logic.dart';
import 'data/store.dart';
import 'screens/auth_screens.dart';
import 'screens/expiry.dart' show navKey;
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  await Api.I.init();
  await Store.I.load();
  runApp(ChangeNotifierProvider<Store>.value(value: Store.I, child: const BookendsApp()));
}

class BookendsApp extends StatelessWidget {
  const BookendsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bookends Cleaning',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scaffoldMessengerKey: scaffoldKey,
        navigatorKey: navKey,
        home: const Gate(),
      );
}

/// Boot: refresh the saved session, fall back to the cached profile when
/// offline, otherwise show the sign-in screen.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  bool _booting = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.I.onSignedOut = () {
      if (mounted && _signedIn) {
        Store.I.stop();
        Store.I.me = null;
        setState(() => _signedIn = false);
        toast('Please sign in again');
      }
    };
    Store.I.onSynced = ensureJobs;
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _signedIn) {
      if (Store.I.offline) {
        _boot();
      } else {
        Store.I.sync();
      }
    }
  }

  Future<void> _boot() async {
    final s = Store.I;
    s.loadConfig();
    try {
      final ok = await Api.I.refresh();
      if (ok) {
        await s.adoptUser(Map<String, dynamic>.from(Api.I.lastSession!['user'] as Map));
        s.offline = false;
        await s.loadRoster();
        _afterSignIn();
      } else {
        s.me = null;
        _signedIn = false;
      }
    } on ApiException catch (e) {
      if (e.isOffline && s.me != null) {
        s.offline = true;
        s.syncState = 'offline';
        _signedIn = true;
        toast('No connection — showing the work saved on this device');
      } else if (!e.isOffline) {
        s.me = null;
      }
    }
    if (mounted) setState(() => _booting = false);
  }

  void _afterSignIn() {
    _signedIn = true;
    ensureJobs();
    if (Store.I.me?['mustChange'] != true) Store.I.start();
  }

  Future<void> _onLogin(Map<String, dynamic> session) async {
    await Store.I.adoptUser(Map<String, dynamic>.from(session['user'] as Map));
    Store.I.offline = false;
    await Store.I.loadRoster();
    setState(_afterSignIn);
  }

  Future<void> _signOut() async {
    await Store.I.signOut();
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('BOOKENDS', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3, color: C.brand)),
            SizedBox(height: 18),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Muted('Signing you in…'),
          ]),
        ),
      );
    }
    final me = context.watch<Store>().me;
    if (!_signedIn || me == null) return LoginScreen(onSignedIn: _onLogin);
    if (me['mustChange'] == true) {
      return SetPasswordScreen(
        onDone: () => setState(() => Store.I.start()),
        onSignOut: _signOut,
      );
    }
    return Shell(onSignOut: _signOut);
  }
}
