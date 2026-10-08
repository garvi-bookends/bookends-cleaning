import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/store.dart';

/// Signed-out screens: sign in, create an account, forgot password, and the
/// forced "choose your password" gate.
class AuthShell extends StatelessWidget {
  final Widget child;
  const AuthShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF8F9FE), Color(0xFFEDF0FA)]),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(children: [
                    const SizedBox(height: 10),
                    const Text('BOOKENDS',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3, color: C.brand)),
                    const SizedBox(height: 4),
                    const Text('KITCHEN OPERATIONS & COMPLIANCE',
                        style: TextStyle(fontSize: 12, color: C.mut, letterSpacing: .8, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 22),
                    child,
                    const SizedBox(height: 22),
                    const Muted('Bookends Cleaning System', size: 12),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

Widget _cardTitle(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Muted(s, size: 14),
      const SizedBox(height: 6),
    ]);

class LoginScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> session) onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _uid = TextEditingController(), _pw = TextEditingController();
  String? _err;
  bool _busy = false;
  String _mode = 'login'; // login | signup | forgot

  Future<void> _login() async {
    final uid = _uid.text.trim().toLowerCase(), pw = _pw.text;
    if (uid.isEmpty || pw.isEmpty) return setState(() => _err = 'Enter your ID and password');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final s = await Api.I.post('/api/auth/login', {'uid': uid, 'password': pw}, false);
      widget.onSignedIn(s);
    } on ApiException catch (e) {
      setState(() => _err = e.isOffline ? 'No connection to the server. Check your internet and try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _server() async {
    final v = await askText(context, 'Server address', 'The web address of the Bookends Cleaning website.',
        initial: Api.I.base, hint: 'https://your-site.vercel.app', ok: 'Save');
    if (v != null && v.trim().isNotEmpty) {
      await Api.I.setBase(v);
      await Store.I.loadConfig();
      setState(() {});
      toast('Server set to ${Api.I.base}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == 'signup') return AuthShell(child: SignupCard(onBack: () => setState(() => _mode = 'login')));
    if (_mode == 'forgot') return AuthShell(child: ForgotCard(onBack: () => setState(() => _mode = 'login')));
    final dp = Store.I.defaultPassword;
    return AuthShell(
      child: Column(children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _cardTitle('Sign in', 'Use your own ID and password.'),
            if (_err != null) ...[const SizedBox(height: 8), InfoCard.red(Text(_err!, style: const TextStyle(fontWeight: FontWeight.w700)))],
            const FieldLabel('User ID'),
            TextField(
              controller: _uid,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(hintText: 'e.g. rahul'),
              textInputAction: TextInputAction.next,
            ),
            const FieldLabel('Password'),
            TextField(controller: _pw, obscureText: true, onSubmitted: (_) => _login()),
            const SizedBox(height: 16),
            Btn(_busy ? 'Signing in…' : 'Sign in', _login, busy: _busy),
          ]),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'First time signing in? Your ID is your first name in lower case and your password is '),
              TextSpan(text: dp, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)),
              const TextSpan(text: '. The app will ask you to choose a new one straight away.'),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.mut, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(onPressed: () => setState(() => _mode = 'signup'), child: const Text('Create an account')),
          const Text('|', style: TextStyle(color: C.chev)),
          TextButton(onPressed: () => setState(() => _mode = 'forgot'), child: const Text('Forgot password?')),
        ]),
        TextButton.icon(
          onPressed: _server,
          icon: const Icon(Icons.dns_outlined, size: 16, color: C.mut),
          label: Text('Server: ${Uri.tryParse(Api.I.base)?.host ?? Api.I.base}', style: const TextStyle(color: C.mut, fontSize: 12)),
        ),
      ]),
    );
  }
}

String? passwordProblem(String pw, String again) {
  final s = Store.I;
  if (pw.length < s.minPasswordLength) return 'Password must be at least ${s.minPasswordLength} characters';
  if (pw != again) return 'The two passwords do not match';
  if (pw == s.defaultPassword) return 'Please choose something other than ${s.defaultPassword}';
  return null;
}

class SignupCard extends StatefulWidget {
  final VoidCallback onBack;
  const SignupCard({super.key, required this.onBack});
  @override
  State<SignupCard> createState() => _SignupCardState();
}

class _SignupCardState extends State<SignupCard> {
  final _name = TextEditingController(), _uid = TextEditingController(), _pw = TextEditingController(), _pw2 = TextEditingController();
  String? _loc, _err, _doneUid;
  bool _busy = false;

  Future<void> _submit() async {
    final name = _name.text.trim(), uid = _uid.text.trim().toLowerCase();
    String? e;
    if (name.length < 2) {
      e = 'Enter your name';
    } else if (!RegExp(r'^[a-z0-9]{2,32}$').hasMatch(uid)) {
      e = 'Username: 2 to 32 lower case letters or numbers, no spaces';
    } else if (_loc == null) {
      e = 'Choose your kitchen';
    } else {
      e = passwordProblem(_pw.text, _pw2.text);
    }
    if (e != null) return setState(() => _err = e);
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Api.I.post('/api/auth/register',
          {'name': name, 'uid': uid, 'loc': _loc, 'password': _pw.text, 'confirmPassword': _pw2.text}, false);
      setState(() => _doneUid = uid);
    } on ApiException catch (x) {
      setState(() => _err = x.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doneUid != null) {
      return AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          const Text('✅', style: TextStyle(fontSize: 40)),
          const Text('Account created', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          Muted('Thanks, ${_name.text.trim().split(' ').first}.'),
          const SizedBox(height: 12),
          InfoCard.blue(Column(children: [
            const Muted('YOUR USERNAME', size: 11),
            Text(_doneUid!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          ])),
          const Muted(
              'Your account now needs to be approved by the Super Admin. Once it is, sign in with this username and the password you just chose.'),
          const SizedBox(height: 14),
          Btn('Back to sign in', widget.onBack),
        ]),
      );
    }
    return Column(children: [
      AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardTitle('Create your account', 'Choose your own username and password.'),
          if (_err != null) InfoCard.red(Text(_err!, style: const TextStyle(fontWeight: FontWeight.w700))),
          const FieldLabel('Your name'),
          TextField(controller: _name, decoration: const InputDecoration(hintText: 'e.g. Suresh Patel')),
          const FieldLabel('Username'),
          TextField(controller: _uid, autocorrect: false, decoration: const InputDecoration(hintText: 'e.g. suresh')),
          const Padding(
              padding: EdgeInsets.only(top: 4, left: 2),
              child: Muted('Lower case letters and numbers only. You will sign in with this.', size: 12)),
          const FieldLabel('Your kitchen'),
          DropdownButtonFormField<String>(
            initialValue: _loc,
            hint: const Text('— choose —'),
            items: [for (final l in kLocations) DropdownMenuItem(value: l.id, child: Text(l.name))],
            onChanged: (v) => setState(() => _loc = v),
          ),
          const FieldLabel('Password'),
          TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(hintText: 'At least ${Store.I.minPasswordLength} characters')),
          const FieldLabel('Type it again'),
          TextField(controller: _pw2, obscureText: true),
          const SizedBox(height: 16),
          Btn(_busy ? 'Creating…' : 'Create account', _submit, busy: _busy),
          const SizedBox(height: 12),
          const Muted('The Super Admin approves your account and sets what you can do. You can sign in once it is approved.'),
        ]),
      ),
      TextButton(onPressed: widget.onBack, child: const Text('I already have an account')),
    ]);
  }
}

class ForgotCard extends StatefulWidget {
  final VoidCallback onBack;
  const ForgotCard({super.key, required this.onBack});
  @override
  State<ForgotCard> createState() => _ForgotCardState();
}

class _ForgotCardState extends State<ForgotCard> {
  final _uid = TextEditingController();
  String? _err, _msg;
  bool _busy = false;

  Future<void> _send() async {
    final uid = _uid.text.trim().toLowerCase();
    if (uid.isEmpty) return setState(() => _err = 'Enter your username');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await Api.I.post('/api/auth/forgot', {'uid': uid}, false);
      setState(() => _msg = (r['message'] ?? 'Request sent') as String);
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_msg != null) {
      return AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          const Text('📨', style: TextStyle(fontSize: 40)),
          const Text('Request sent', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_msg!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Muted('When you sign in with the temporary password, you will be asked to choose your own.'),
          const SizedBox(height: 14),
          Btn('Back to sign in', widget.onBack),
        ]),
      );
    }
    return Column(children: [
      AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardTitle('Forgot your password?', 'Enter your username. The Super Admin will set a temporary password for you.'),
          if (_err != null) InfoCard.red(Text(_err!, style: const TextStyle(fontWeight: FontWeight.w700))),
          const FieldLabel('Username'),
          TextField(controller: _uid, autocorrect: false, decoration: const InputDecoration(hintText: 'e.g. rahul')),
          const SizedBox(height: 16),
          Btn(_busy ? 'Sending…' : 'Ask for a new password', _send, busy: _busy),
        ]),
      ),
      TextButton(onPressed: widget.onBack, child: const Text('Back to sign in')),
    ]);
  }
}

/// Shown while the account still has its starting password.
class SetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone, onSignOut;
  const SetPasswordScreen({super.key, required this.onDone, required this.onSignOut});
  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _pw = TextEditingController(), _pw2 = TextEditingController();
  String? _err;
  bool _busy = false;

  Future<void> _save() async {
    final e = passwordProblem(_pw.text, _pw2.text);
    if (e != null) return setState(() => _err = e);
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await Api.I.post('/api/auth/change-password',
          {'currentPassword': '', 'newPassword': _pw.text, 'confirmPassword': _pw2.text});
      await Store.I.adoptUser(Map<String, dynamic>.from(r['user'] as Map));
      Store.I.me!['mustChange'] = false;
      Store.I.logAct('user', 'Password changed');
      toast('Password updated');
      widget.onDone();
    } on ApiException catch (x) {
      setState(() => _err = x.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Store.I.me ?? {};
    return AuthShell(
      child: Column(children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _cardTitle('Choose your password', '${me['name']} · ID ${me['uid']}'),
            if (_err != null) InfoCard.red(Text(_err!, style: const TextStyle(fontWeight: FontWeight.w700))),
            const FieldLabel('New password'),
            TextField(
                controller: _pw,
                obscureText: true,
                decoration: InputDecoration(hintText: 'At least ${Store.I.minPasswordLength} characters')),
            const FieldLabel('Type it again'),
            TextField(controller: _pw2, obscureText: true, onSubmitted: (_) => _save()),
            const SizedBox(height: 16),
            Btn(_busy ? 'Saving…' : 'Save and continue', _save, busy: _busy),
            const SizedBox(height: 12),
            const Muted(
                'Replace the starting password before you use the app. Keep it to yourself — everything you do is recorded under your name.'),
          ]),
        ),
        TextButton(onPressed: widget.onSignOut, child: const Text('Sign in as someone else')),
      ]),
    );
  }
}
