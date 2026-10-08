import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'cleaning.dart';
import 'shell.dart';

// ---------------------------------------------------------------------------
// Approvals (Super Admin only — server APPROVER_ROLES)
// ---------------------------------------------------------------------------
List<Rec> tasksAwaitingApproval() {
  if (!S.perm.approve) return [];
  return S.tasks.values.where((t) => t['status'] == 'completed' && t['approved'] != true && taskLive(t)).toList()
    ..sort((a, b) => ((b['completedAt'] as num?) ?? 0).compareTo((a['completedAt'] as num?) ?? 0));
}

void approveTask(Rec t) {
  t
    ..['status'] = 'completed'
    ..['approved'] = true
    ..['approvedBy'] = S.myId
    ..['approvedAt'] = DateTime.now().millisecondsSinceEpoch
    ..['reject'] = '';
  S.touch('tasks', t);
  S.logAct('approve', 'Approved: ${cleanName(t)}', t['loc'] as String?);
  toast('Approved ✓');
}

Future<bool> rejectTask(BuildContext context, Rec t) async {
  final reason = await askText(context, 'Reject this job', 'The person who did it will see this reason.',
      initial: 'Area re-do required', hint: 'What was wrong?', ok: 'Reject', danger: true);
  if (reason == null) return false;
  t
    ..['status'] = 'rejected'
    ..['approved'] = false
    ..['approvedBy'] = S.myId
    ..['approvedAt'] = DateTime.now().millisecondsSinceEpoch
    ..['reject'] = reason.trim().isEmpty ? 'Rejected' : reason.trim()
    ..['before'] = null
    ..['after'] = null;
  S.touch('tasks', t);
  S.logAct('reject', 'Rejected: ${cleanName(t)}', t['loc'] as String?);
  toast('Rejected — team notified');
  return true;
}

// ---------------------------------------------------------------------------
// Admin user list (sign-ups, reset requests)
// ---------------------------------------------------------------------------
List<Rec> adminUsers = [];
int get adminQueueCount =>
    adminUsers.where((u) => u['pending'] == true).length + adminUsers.where((u) => u['resetRequestedAt'] != null).length;

Future<void> refreshAdminQueue() async {
  if (!S.perm.superadmin) return;
  try {
    final r = await Api.I.get('/api/admin/users');
    adminUsers = ((r['users'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    S.save();
  } catch (_) {}
}

class AdminQueueCards extends StatefulWidget {
  const AdminQueueCards({super.key});
  @override
  State<AdminQueueCards> createState() => _AdminQueueCardsState();
}

class _AdminQueueCardsState extends State<AdminQueueCards> {
  @override
  void initState() {
    super.initState();
    refreshAdminQueue().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final pend = adminUsers.where((u) => u['pending'] == true).length;
    final resets = adminUsers.where((u) => u['resetRequestedAt'] != null).length;
    return Column(children: [
      if (pend > 0)
        _queue('👤', '$pend new account${pend == 1 ? '' : 's'} waiting for approval',
            'Someone signed up. Tap to choose their role and approve or reject.', 'Review ›', () => navState.go('manage', manageTo: 'users')),
      if (resets > 0)
        _queue('🔑', '$resets password reset request${resets == 1 ? '' : 's'}',
            'Someone forgot their password. Tap to set a temporary one.', 'Open ›', () => navState.go('manage', manageTo: 'users')),
    ]);
  }

  Widget _queue(String e, String t, String s, String cta, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          color: const Color(0xFFFFF7E2),
          border: const Color(0xFFF6DFA3),
          onTap: onTap,
          child: Row(children: [
            Text(e, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
                Muted(s, size: 12.5),
              ]),
            ),
            Text(cta, style: const TextStyle(fontWeight: FontWeight.w800, color: C.brand)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Management screens
// ---------------------------------------------------------------------------
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final nav = context.watch<Nav>();
    switch (nav.manage) {
      case 'users':
        return const UserManagement();
      case 'jobs':
        return const JobManagement();
      case 'review':
        return const TaskReview();
    }
    context.watch<Store>();
    final waiting = tasksAwaitingApproval().length;
    return Column(children: [
      const PageHeader('MANAGEMENT', sub: 'Super Admin', showLoc: false),
      Expanded(
        child: PageBody(onRefresh: () async {
          await S.sync();
          await refreshAdminQueue();
        }, children: [
          const AdminQueueCards(),
          RowsCard([
            LRow(
                leading: const Tile('👥', Color(0xFFEEF2FF)),
                title: 'User Management',
                sub: 'Users, roles and assignments',
                pills: [if (adminQueueCount > 0) Pill('$adminQueueCount WAITING', PillTone.org)],
                onTap: () => nav.go('manage', manageTo: 'users')),
            LRow(
                leading: const Tile('💼', Color(0xFFFFF7E2)),
                title: 'Job Management',
                sub: 'Job types, services and setup',
                onTap: () => nav.go('manage', manageTo: 'jobs')),
            LRow(
                leading: const Tile('✅', Color(0xFFE8F0FB)),
                title: 'Task Review',
                sub: 'Approve or reject completed work',
                pills: [if (waiting > 0) Pill('$waiting WAITING', PillTone.org)],
                onTap: () => nav.go('manage', manageTo: 'review')),
          ]),
        ]),
      ),
    ]);
  }
}

Widget _back(BuildContext context, [String to = 'home']) => GestureDetector(
      onTap: () => navState.go('manage', manageTo: to),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
    );

// ---------------------------------------------------------------------------
// Task Review
// ---------------------------------------------------------------------------
class TaskReview extends StatefulWidget {
  const TaskReview({super.key});
  @override
  State<TaskReview> createState() => _TaskReviewState();
}

class _TaskReviewState extends State<TaskReview> {
  String q = '';

  String _state(Rec t) => t['status'] == 'rejected' ? 'rejected' : (t['approved'] == true ? 'approved' : 'waiting');

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final nav = context.watch<Nav>();
    final all = S.tasks.values
        .where((t) => taskLive(t) && (t['status'] == 'rejected' || t['status'] == 'completed'))
        .toList()
      ..sort((a, b) => ((b['completedAt'] as num?) ?? 0).compareTo((a['completedAt'] as num?) ?? 0));
    int n(String k) => all.where((t) => _state(t) == k).length;
    final f = nav.reviewFilter;
    final ql = q.toLowerCase();
    final shown = all.where((t) {
      if (f != 'all' && _state(t) != f) return false;
      if (ql.isEmpty) return true;
      return '${uname((t['completedBy'] ?? t['assigned']) as String?)} ${cleanName(t)} ${locName(t['loc'] as String?)} ${t['jobType'] ?? 'cleaning'}'
          .toLowerCase()
          .contains(ql);
    }).toList();
    final people = all.map((t) => t['completedBy'] ?? t['assigned']).toSet().length;

    return Column(children: [
      PageHeader('TASK REVIEW', sub: 'Management · Super Admin', showLoc: false, leading: _back(context)),
      Expanded(
        child: PageBody(children: [
          StatGrid([
            Stat('${n('waiting')}', 'Waiting', color: C.org),
            Stat('${n('approved')}', 'Approved', color: C.grn),
            Stat('${n('rejected')}', 'Rejected', color: C.red),
            Stat('$people', 'People'),
          ], maxCols: 4),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(hintText: 'Person, job, restaurant or job type', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 10),
          ChipRow([
            ('all', 'All ${all.length}'),
            ('waiting', 'Waiting ${n('waiting')}'),
            ('approved', 'Approved ${n('approved')}'),
            ('rejected', 'Rejected ${n('rejected')}'),
          ], f, (k) {
            nav.reviewFilter = k;
            nav.refresh();
          }),
          SecTitle('Sent for approval · ${shown.length}'),
          if (shown.isEmpty)
            const EmptyState('✅', 'Nothing here')
          else
            for (final t in shown.take(200))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => taskSheet(context, t['id'] as String),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((t['after'] ?? t['before']) != null)
                      Photo((t['after'] ?? t['before']) as String, width: 64, height: 64)
                    else
                      const Tile('🧽', Color(0xFFE8F0FB), size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cleanName(t), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Muted(
                            '${uname((t['completedBy'] ?? t['assigned']) as String?)} · ${locById(t['loc'] as String?)?.name} · ${t['zone'] ?? ''}',
                            size: 12.5),
                        Muted('Due ${fmtD(t['due'] as String?)} · done ${fmtDT((t['completedAt'] as num?)?.toInt())}', size: 12.5),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          statusPill(t),
                          if ((t['after'] ?? t['before']) == null) const Pill('NO PHOTO', PillTone.org),
                        ]),
                        if (_state(t) == 'rejected' && '${t['reject']}'.isNotEmpty)
                          Text('${t['reject']}', style: const TextStyle(color: C.red, fontSize: 12.5)),
                        if (_state(t) == 'waiting') ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: Btn('✓ Approve', () => approveTask(t), kind: BtnKind.ok, small: true)),
                            const SizedBox(width: 8),
                            Expanded(child: Btn('✕ Reject', () => rejectTask(context, t), kind: BtnKind.no, small: true)),
                          ]),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
          const Muted(
              'Only this account can approve or reject. Everyone else records the work and sends it here. Approved and rejected work stays on this page.',
              size: 12),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// User Management
// ---------------------------------------------------------------------------
class UserManagement extends StatefulWidget {
  const UserManagement({super.key});
  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  String q = '', f = 'all';
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.I.get('/api/admin/users');
      adminUsers = ((r['users'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      err = null;
    } on ApiException catch (e) {
      err = e.message;
    }
    if (mounted) setState(() => loading = false);
    S.loadRoster();
  }

  String _status(Rec u) => u['pending'] == true ? 'pending' : (u['disabled'] == true ? 'disabled' : 'active');

  @override
  Widget build(BuildContext context) {
    final users = adminUsers;
    int n(String k) => users.where((u) => _status(u) == k).length;
    final ql = q.toLowerCase();
    final shown = users.where((u) {
      if (f != 'all' && _status(u) != f) return false;
      return ql.isEmpty ||
          '${u['name']} ${u['email']} ${u['uid']} ${roleOf(u['role'] as String?).label} ${locName(u['loc'] as String?)}'
              .toLowerCase()
              .contains(ql);
    }).toList();
    final resets = users.where((u) => u['resetRequestedAt'] != null).toList();

    return Column(children: [
      PageHeader('USER MANAGEMENT', sub: 'Management · Super Admin', showLoc: false, leading: _back(context)),
      Expanded(
        child: PageBody(onRefresh: _load, children: [
          if (loading) const LinearProgressIndicator(),
          if (err != null) InfoCard.red(Text(err!)),
          StatGrid([
            Stat('${users.length}', 'Total users'),
            Stat('${n('active')}', 'Active', color: C.grn),
            Stat('${n('pending')}', 'Pending', color: n('pending') > 0 ? C.org : C.mut),
          ]),
          const SizedBox(height: 10),
          Btn('＋ Add User', () => _userForm(context, null)),
          if (resets.isNotEmpty) ...[
            SecTitle('Password reset requests (${resets.length})'),
            RowsCard([
              for (final u in resets)
                LRow(
                  leading: const Tile('🔑', Color(0xFFFFF7E2)),
                  title: '${u['name']}',
                  sub: '${u['uid']} · asked ${fmtDT(DateTime.tryParse('${u['resetRequestedAt']}')?.millisecondsSinceEpoch ?? (u['resetRequestedAt'] is num ? (u['resetRequestedAt'] as num).toInt() : null))}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => _resetPw(context, u), child: const Text('Set new')),
                    IconButton(
                      icon: const Icon(Icons.close, color: C.mut),
                      onPressed: () async {
                        if (!await askConfirm(context, 'Dismiss this request?',
                            'Their password stays as it is. Only do this if they no longer need a reset.', 'Dismiss')) {
                          return;
                        }
                        await _call(() => Api.I.post('/api/admin/users/${u['id']}/dismiss-reset'), 'Request dismissed');
                      },
                    ),
                  ]),
                ),
            ]),
          ],
          if (n('pending') > 0) ...[
            SecTitle('${n('pending')} sign-up${n('pending') == 1 ? '' : 's'} waiting for you'),
            RowsCard([
              for (final u in users.where((u) => u['pending'] == true))
                LRow(
                  leading: const Tile('👤', Color(0xFFFFF7E2)),
                  title: '${u['name']}',
                  sub: '${u['uid']} · ${locName(u['loc'] as String?)}',
                  onTap: () => _approve(context, u),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(hintText: 'Name, email, username, role or kitchen', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 10),
          ChipRow([
            ('all', 'All ${users.length}'),
            ('active', 'Active ${n('active')}'),
            ('pending', 'Pending ${n('pending')}'),
            ('disabled', 'Disabled ${n('disabled')}'),
          ], f, (k) => setState(() => f = k)),
          SecTitle('Accounts · ${shown.length}'),
          RowsCard([
            for (final u in shown)
              LRow(
                leading: Tile(initials(u['name'] as String?), const Color(0xFFEEF2FF)),
                title: '${u['name']}${u['id'] == S.myId ? ' · you' : ''}',
                sub: [
                  '${u['uid']}',
                  roleOf(u['role'] as String?).label,
                  roleOf(u['role'] as String?).all ? 'All 8' : locName(u['loc'] as String?),
                  u['lastLogin'] == null ? 'Has never signed in' : 'Last sign-in ${_dt(u['lastLogin'])} · ${u['loginCount'] ?? 0} total',
                  if (u['mustChange'] == true) 'Still on the starting password',
                ].join(' · '),
                pills: [
                  switch (_status(u)) {
                    'pending' => const Pill('PENDING', PillTone.org),
                    'disabled' => const Pill('DISABLED', PillTone.red),
                    _ => const Pill('ACTIVE', PillTone.grn),
                  },
                  for (final j in ((u['jobTypes'] as List?) ?? const [])) Pill('$j'.toUpperCase(), PillTone.gry),
                ],
                onTap: () => u['pending'] == true ? _approve(context, u) : _userActions(context, u),
              ),
          ]),
        ]),
      ),
    ]);
  }

  String _dt(dynamic v) {
    if (v is num) return fmtDT(v.toInt());
    final d = DateTime.tryParse('$v');
    return d == null ? '—' : fmtDT(d.millisecondsSinceEpoch);
  }

  Future<bool> _call(Future<dynamic> Function() f, String ok) async {
    try {
      await f();
      toast(ok);
      await _load();
      return true;
    } on ApiException catch (e) {
      toast(e.message);
      return false;
    }
  }

  void _userActions(BuildContext context, Rec u) {
    final isSuper = u['role'] == 'superadmin';
    final self = u['id'] == S.myId;
    showSheet(context, '${u['name']}', (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            child: Column(children: [
              KV.text('Username', '${u['uid']}', bold: true),
              KV.text('Role', roleOf(u['role'] as String?).label),
              KV.text('Restaurant', roleOf(u['role'] as String?).all ? 'All 8 kitchens' : locName(u['loc'] as String?)),
              KV.text('Email', '${u['email'] ?? ''}'.isEmpty ? '—' : '${u['email']}'),
              KV.text('Last sign-in', u['lastLogin'] == null ? 'Never' : _dt(u['lastLogin'])),
              KV.text('Password', '🔒 encrypted'),
            ]),
          ),
          const SizedBox(height: 12),
          Btn('✏️ Edit', () {
            Navigator.pop(ctx);
            _userForm(context, u);
          }, kind: BtnKind.sec),
          const SizedBox(height: 8),
          Btn('🔑 Reset password', () {
            Navigator.pop(ctx);
            _resetPw(context, u);
          }, kind: BtnKind.sec),
          if (!isSuper && !self) ...[
            const SizedBox(height: 8),
            Btn(u['disabled'] == true ? '▶ Enable' : '⏸ Disable', () async {
              final dis = u['disabled'] != true;
              if (dis &&
                  !await askConfirm(ctx, 'Disable this user?',
                      'Are you sure you want to disable “${u['name']}”? They will not be able to sign in. Their recorded work is kept.', 'Disable',
                      danger: true)) {
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _call(() => Api.I.patch('/api/admin/users/${u['id']}', {'disabled': dis}), '${u['name']} ${dis ? 'disabled' : 'enabled'}');
              S.logAct('user', '${dis ? 'Disabled' : 'Enabled'} ${u['name']}');
            }, kind: BtnKind.sec),
            const SizedBox(height: 8),
            Btn('✕ Remove', () async {
              if (!await askConfirm(ctx, 'Remove ${u['name']}?', 'They will no longer be able to sign in. Work they already recorded is kept.',
                  'Remove',
                  danger: true)) {
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _call(() => Api.I.delete('/api/admin/users/${u['id']}'), '${u['name']} removed');
              S.logAct('user', 'Removed ${u['name']}');
            }, kind: BtnKind.no),
          ],
        ]));
  }

  void _approve(BuildContext context, Rec u) {
    var role = 'staff';
    String? loc = u['loc'] as String?;
    showSheet(context, 'Approve ${u['name']}', (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Muted('Username ${u['uid']} · asked for ${locName(u['loc'] as String?)}'),
            const FieldLabel('Role'),
            DropdownButtonFormField<String>(
              initialValue: role,
              items: [for (final r in assignableRoles) DropdownMenuItem(value: r, child: Text(roleOf(r).label))],
              onChanged: (v) => set(() => role = v!),
            ),
            if (!roleOf(role).all) ...[
              const FieldLabel('Kitchen'),
              DropdownButtonFormField<String>(
                initialValue: loc,
                hint: const Text('— choose —'),
                items: [for (final l in kLocations) DropdownMenuItem(value: l.id, child: Text('${l.code} ${l.name}'))],
                onChanged: (v) => set(() => loc = v),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Btn('✕ Reject', () async {
                  if (!await askConfirm(ctx, 'Reject ${u['name']}?', 'The account is deleted. They can sign up again if it was a mistake.',
                      'Reject',
                      danger: true)) {
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _call(() => Api.I.delete('/api/admin/users/${u['id']}'), 'Sign-up rejected');
                }, kind: BtnKind.no),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn('✓ Approve', () async {
                  if (!roleOf(role).all && loc == null) return toast('Choose which kitchen they work in');
                  Navigator.pop(ctx);
                  if (await _call(() => Api.I.post('/api/admin/users/${u['id']}/approve', {'role': role, 'loc': loc}),
                      '${u['name']} approved')) {
                    S.logAct('user', 'Approved ${u['name']} (${u['uid']}) as ${roleOf(role).label}');
                  }
                }, kind: BtnKind.ok),
              ),
            ]),
          ]);
        }));
  }

  void _resetPw(BuildContext context, Rec u) {
    final pw = TextEditingController(), pw2 = TextEditingController();
    showSheet(context, 'Reset password · ${u['name']}', (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const InfoCard(Text(
              'They are signed out on every device, and must choose their own password the next time they sign in.')),
          const FieldLabel('New password'),
          TextField(controller: pw, decoration: InputDecoration(hintText: 'leave blank for ${S.defaultPassword}')),
          const FieldLabel('Confirm new password'),
          TextField(controller: pw2),
          const SizedBox(height: 16),
          Btn('Reset Password', () async {
            if (pw.text != pw2.text) return toast('The two passwords do not match');
            try {
              final r = await Api.I.post('/api/admin/users/${u['id']}/reset-password', {if (pw.text.isNotEmpty) 'password': pw.text});
              if (ctx.mounted) Navigator.pop(ctx);
              S.logAct('user', 'New password set for ${u['name']}');
              await _load();
              if (context.mounted) _showCreds(context, 'New password set', '${u['uid']}', '${r['password'] ?? (pw.text.isEmpty ? S.defaultPassword : pw.text)}');
            } on ApiException catch (e) {
              toast(e.message);
            }
          }, kind: BtnKind.no),
        ]));
  }

  void _showCreds(BuildContext context, String title, String uid, String pw) {
    showSheet(context, title, (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: Text('✅', style: TextStyle(fontSize: 40))),
          AppCard(
            child: Column(children: [
              const Muted('LOGIN ID', size: 11),
              SelectableText(uid, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Muted('PASSWORD', size: 11),
              SelectableText(pw, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 10),
          const Muted('Give these to them now — the password is not shown again. They must choose their own when they first sign in.'),
          const SizedBox(height: 12),
          Btn('Done', () => Navigator.pop(ctx)),
        ]));
  }

  void _userForm(BuildContext context, Rec? u) {
    final name = TextEditingController(text: '${u?['name'] ?? ''}');
    final email = TextEditingController(text: '${u?['email'] ?? ''}');
    final uid = TextEditingController(text: '${u?['uid'] ?? ''}');
    final pw = TextEditingController();
    var role = (u?['role'] ?? 'staff') as String;
    String? loc = u?['loc'] as String?;
    var disabled = u?['disabled'] == true;
    final types = <String>{...((u?['jobTypes'] as List?) ?? const []).map((e) => '$e')};
    final isSuper = role == 'superadmin';
    showSheet(context, u == null ? 'Create a new user' : 'Edit User', (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Full name'),
            TextField(
              controller: name,
              decoration: const InputDecoration(hintText: 'e.g. Suresh'),
              onChanged: u != null
                  ? null
                  : (v) async {
                      if (v.trim().isEmpty) return;
                      try {
                        final r = await Api.I.get('/api/admin/users/suggest-uid', query: {'name': v.trim()});
                        set(() => uid.text = '${r['uid'] ?? ''}');
                      } catch (_) {}
                    },
            ),
            const FieldLabel('Email'),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Optional')),
            const FieldLabel('Login ID'),
            TextField(
                controller: uid,
                enabled: u == null,
                decoration: InputDecoration(hintText: u == null ? 'filled in automatically' : null)),
            if (u != null) const Muted('A username is never changed — it is what their recorded work is filed under.', size: 12),
            const FieldLabel('Role'),
            DropdownButtonFormField<String>(
              initialValue: role,
              items: [
                for (final r in isSuper ? ['superadmin'] : assignableRoles) DropdownMenuItem(value: r, child: Text(roleOf(r).label)),
              ],
              onChanged: isSuper ? null : (v) => set(() => role = v!),
            ),
            if (!roleOf(role).all) ...[
              const FieldLabel('Location'),
              DropdownButtonFormField<String>(
                initialValue: loc,
                hint: const Text('— choose —'),
                items: [for (final l in kLocations) DropdownMenuItem(value: l.id, child: Text('${l.code} ${l.name}'))],
                onChanged: (v) => set(() => loc = v),
              ),
            ],
            if (u == null) ...[
              const FieldLabel('Initial password'),
              TextField(controller: pw, decoration: InputDecoration(hintText: 'leave blank for ${S.defaultPassword}')),
            ],
            if (!isSuper) ...[
              const FieldLabel('Account status'),
              DropdownButtonFormField<bool>(
                initialValue: disabled,
                items: const [
                  DropdownMenuItem(value: false, child: Text('Active — can sign in')),
                  DropdownMenuItem(value: true, child: Text('Disabled — cannot sign in')),
                ],
                onChanged: (v) => set(() => disabled = v!),
              ),
            ],
            const FieldLabel('Job types'),
            Wrap(children: [
              for (final t in S.jobTypes)
                AppChip('${t['name']}', types.contains(t['id']), () => set(() {
                      final id = '${t['id']}';
                      types.contains(id) ? types.remove(id) : types.add(id);
                    })),
            ]),
            const Muted('Leave all unselected for every job type.', size: 12),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Btn('Cancel', () => Navigator.pop(ctx), kind: BtnKind.sec)),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(u == null ? 'Create user' : 'Save Changes', () async {
                  if (name.text.trim().length < 2) return toast('Enter their full name');
                  if (!roleOf(role).all && loc == null) return toast('Choose which kitchen they work in');
                  try {
                    if (u == null) {
                      final r = await Api.I.post('/api/admin/users', {
                        'name': name.text.trim(),
                        if (uid.text.trim().isNotEmpty) 'uid': uid.text.trim().toLowerCase(),
                        'role': role,
                        'loc': roleOf(role).all ? null : loc,
                        if (pw.text.isNotEmpty) 'password': pw.text,
                        'disabled': disabled,
                        'email': email.text.trim(),
                        'jobTypes': types.toList(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      final nu = Map<String, dynamic>.from(r['user'] as Map);
                      S.logAct('user', 'Created user ${nu['name']} (${nu['uid']}) as ${roleOf(role).label}');
                      await _load();
                      if (context.mounted) _showCreds(context, 'User created', '${nu['uid']}', '${r['initialPassword'] ?? S.defaultPassword}');
                    } else {
                      await Api.I.patch('/api/admin/users/${u['id']}', {
                        'name': name.text.trim(),
                        'email': email.text.trim(),
                        'jobTypes': types.toList(),
                        if (!isSuper) 'role': role,
                        if (!isSuper) 'loc': roleOf(role).all ? null : loc,
                        if (!isSuper && u['id'] != S.myId) 'disabled': disabled,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      toast('${name.text.trim()} updated');
                      S.logAct('user', 'Updated ${name.text.trim()} (${u['uid']}) — ${roleOf(role).label}');
                      await _load();
                    }
                  } on ApiException catch (e) {
                    toast(e.message);
                  }
                }),
              ),
            ]),
          ]);
        }));
  }
}

// ---------------------------------------------------------------------------
// Job Management
// ---------------------------------------------------------------------------
class JobManagement extends StatefulWidget {
  const JobManagement({super.key});
  @override
  State<JobManagement> createState() => _JobManagementState();
}

class _JobManagementState extends State<JobManagement> {
  String? openType;
  String q = '', f = 'all';

  @override
  void initState() {
    super.initState();
    S.pullChecklist().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Every service (built-in template + custom) as resolved jobs.
  List<(Job, Rec?)> _services(String type) {
    final out = <(Job, Rec?)>[];
    for (final b in [...kBuiltinWeekly, ...kBuiltinMonthly]) {
      final o = S.checklist[b.tk];
      if (o?['deleted'] == true) continue;
      final j = jobFor(b.tk)!;
      if (j.jobType == type) out.add((j, o));
    }
    for (final o in S.checklist.values) {
      if (o['custom'] == true && o['deleted'] != true) {
        final j = jobFor(o['tkey'] as String);
        if (j != null && j.jobType == type) out.add((j, o));
      }
    }
    return out;
  }

  Future<void> _patch(String tk, Map<String, dynamic> body, String msg) async {
    try {
      final b = builtinByTk(tk);
      final r = await Api.I.patch('/api/checklist/items/$tk', {...body, if (b != null) 'builtInName': b.t.area});
      S.checklist[tk] = Map<String, dynamic>.from(r['item'] as Map);
      S.save();
      ensureJobs();
      toast(msg);
      setState(() {});
    } on ApiException catch (e) {
      toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    if (openType != null) return _typeScreen(context, openType!);
    final types = S.jobTypes;
    final all = types.length;
    return Column(children: [
      PageHeader('JOB MANAGEMENT', sub: 'Management · Super Admin', showLoc: false, leading: _back(context)),
      Expanded(
        child: PageBody(onRefresh: () async {
          await S.pullChecklist();
          setState(() {});
        }, children: [
          StatGrid([
            Stat('$all', 'Job types'),
            Stat('${types.where((t) => t['active'] == true).length}', 'Active', color: C.grn),
            Stat('${S.checklist.values.where((o) => o['enabled'] == true && o['deleted'] != true).length}', 'Services', color: C.blue),
          ]),
          const SizedBox(height: 10),
          Btn('＋ Add Job Type', () => _typeForm(context, null)),
          const Padding(padding: EdgeInsets.only(top: 6), child: Muted('Open a job type below to add jobs to it.', size: 12)),
          SecTitle('Job types · $all'),
          if (types.isEmpty)
            const EmptyState('💼', 'No job types loaded')
          else
            RowsCard([
              for (final t in types)
                LRow(
                  leading: const Tile('💼', Color(0xFFFFF7E2)),
                  title: '${t['name']}${t['builtin'] == true ? ' · built in' : ''}',
                  sub: '${t['description'] ?? ''}',
                  pills: [
                    t['active'] == true ? const Pill('ACTIVE', PillTone.grn) : const Pill('INACTIVE', PillTone.red),
                    if (t['id'] != 'labelling' && t['id'] != 'checklist')
                      Pill('${_services('${t['id']}').length} services', PillTone.gry),
                  ],
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) async {
                      if (a == 'edit') _typeForm(context, t);
                      if (a == 'toggle') {
                        try {
                          final r = await Api.I.patch('/api/checklist/types/${t['id']}', {'active': t['active'] != true});
                          await S.pullChecklist();
                          toast('${t['name']} ${(r['type'] as Map)['active'] == true ? 'activated' : 'deactivated'}');
                          setState(() {});
                        } on ApiException catch (e) {
                          toast(e.message);
                        }
                      }
                      if (a == 'delete' && context.mounted) {
                        if (!await askConfirm(context, 'Delete Job Type?',
                            'Are you sure you want to delete “${t['name']}”? A job type with services cannot be removed — switch it off instead.',
                            'Delete',
                            danger: true)) {
                          return;
                        }
                        try {
                          await Api.I.delete('/api/checklist/types/${t['id']}');
                          await S.pullChecklist();
                          setState(() {});
                        } on ApiException catch (e) {
                          toast(e.message);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('✏️ Edit')),
                      PopupMenuItem(value: 'toggle', child: Text(t['active'] == true ? '⏸ Switch off' : '▶ Switch on')),
                      if (t['builtin'] != true) const PopupMenuItem(value: 'delete', child: Text('✕ Delete')),
                    ],
                  ),
                  onTap: t['id'] == 'labelling'
                      ? () => navState.go('lab')
                      : (t['id'] == 'checklist' ? () => navState.go('chk') : () => setState(() => openType = '${t['id']}')),
                ),
            ]),
        ]),
      ),
    ]);
  }

  void _typeForm(BuildContext context, Rec? t) {
    final name = TextEditingController(text: '${t?['name'] ?? ''}');
    final desc = TextEditingController(text: '${t?['description'] ?? ''}');
    var active = t?['active'] != false;
    showSheet(context, t == null ? 'Add Job Type' : 'Edit Job Type', (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Job Type Name (required)'),
            TextField(controller: name, maxLength: 60, decoration: const InputDecoration(hintText: 'e.g. Food Safety')),
            const FieldLabel('Description'),
            TextField(controller: desc, maxLength: 300, decoration: const InputDecoration(hintText: 'e.g. Daily food safety checks')),
            const FieldLabel('Status'),
            DropdownButtonFormField<bool>(
              initialValue: active,
              items: const [
                DropdownMenuItem(value: true, child: Text('Active')),
                DropdownMenuItem(value: false, child: Text('Inactive — not scheduled')),
              ],
              onChanged: (v) => set(() => active = v!),
            ),
            if (t?['builtin'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Muted('${t!['name']} is built into the app. It can be renamed or switched off, but not removed.', size: 12),
              ),
            const SizedBox(height: 16),
            Btn(t == null ? 'Add Job Type' : 'Save Changes', () async {
              if (name.text.trim().isEmpty) return toast('Enter a job type name');
              try {
                final body = {'name': name.text.trim(), 'description': desc.text.trim(), 'active': active};
                if (t == null) {
                  await Api.I.post('/api/checklist/types', body);
                } else {
                  await Api.I.patch('/api/checklist/types/${t['id']}', body);
                }
                S.logAct('user', 'Job type ${t == null ? 'added' : 'updated'}: ${name.text.trim()}');
                await S.pullChecklist();
                if (ctx.mounted) Navigator.pop(ctx);
                toast(t == null ? '“${name.text.trim()}” added' : 'Job type updated');
                setState(() {});
              } on ApiException catch (e) {
                toast(e.message);
              }
            }),
          ]);
        }));
  }

  Widget _typeScreen(BuildContext context, String type) {
    final t = S.jobTypes.where((x) => x['id'] == type).firstOrNull ?? {'name': type};
    final svcs = _services(type);
    final ql = q.toLowerCase();
    final shown = svcs.where((s) {
      final live = serviceLive(s.$1.tk);
      if (f == 'active' && !live) return false;
      if (f == 'off' && live) return false;
      return ql.isEmpty || '${s.$1.name} ${s.$1.zone}'.toLowerCase().contains(ql);
    }).toList();
    final atAll = svcs.where((s) => s.$1.locs == null && serviceLive(s.$1.tk)).length;
    return Column(children: [
      PageHeader('${t['name']}'.toUpperCase(),
          sub: 'Job Management · ${svcs.length} services',
          showLoc: false,
          leading: GestureDetector(
            onTap: () => setState(() => openType = null),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          )),
      Expanded(
        child: PageBody(children: [
          StatGrid([
            Stat('${svcs.length}', 'Services'),
            Stat('${svcs.where((s) => s.$1.freq == 'W').length}', 'Weekly'),
            Stat('${svcs.where((s) => s.$1.freq == 'M').length}', 'Monthly'),
            Stat('${svcs.where((s) => s.$1.freq == 'D').length}', 'Daily'),
            Stat('${svcs.where((s) => serviceLive(s.$1.tk)).length}', 'Active', color: C.grn),
            Stat('$atAll', 'At every kitchen', color: atAll > 0 ? C.org : C.mut),
          ]),
          if (t['active'] == false)
            const InfoCard.red(Text('This job type is switched off. Its services are not scheduled.')),
          const SizedBox(height: 10),
          Btn('＋ Add Service', () => _serviceForm(context, type, null), kind: BtnKind.ok),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(hintText: 'Service name or area', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 10),
          ChipRow([
            ('all', 'All ${svcs.length}'),
            ('active', 'Active ${svcs.where((s) => serviceLive(s.$1.tk)).length}'),
            ('off', 'Off ${svcs.where((s) => !serviceLive(s.$1.tk)).length}'),
          ], f, (k) => setState(() => f = k)),
          SecTitle('Services · ${shown.length}'),
          if (shown.isEmpty)
            const EmptyState('💼', 'Nothing here')
          else
            RowsCard([
              for (final (j, _) in shown)
                LRow(
                  title: j.name,
                  sub: [
                    j.zone,
                    {'D': 'Daily', 'W': 'Weekly', 'M': 'Monthly'}[j.freq] ?? j.freq,
                    if (j.freq == 'W') j.day == null ? 'spread across the week' : 'every ${kDayNames[j.day!]}',
                    j.locs == null ? 'All 8' : (j.locs!.length == 1 ? locById(j.locs!.first)!.code : '${locById(j.locs!.first)!.code} +${j.locs!.length - 1}'),
                    j.assignees.isEmpty ? 'Anyone on shift' : j.assignees.map((a) => uname(a).split(' ').first).join(', '),
                  ].join(' · '),
                  pills: [serviceLive(j.tk) ? const Pill('ACTIVE', PillTone.grn) : const Pill('OFF', PillTone.org)],
                  onTap: () => _serviceForm(context, type, j),
                ),
            ]),
          const SizedBox(height: 8),
          const Muted('Built-in jobs start switched off. Open one and switch it on to start scheduling it.', size: 12),
        ]),
      ),
    ]);
  }

  void _serviceForm(BuildContext context, String type, Job? j) {
    final name = TextEditingController(text: j?.name ?? '');
    final zone = TextEditingController(text: j?.zone ?? '');
    var freq = j?.freq ?? 'W';
    int? day = j?.day;
    final locs = <String>{...?j?.locs};
    final people = <String>{...?j?.assignees};
    String? endDate = j?.endDate;
    String? atTime = j?.atTime;
    var enabled = j == null ? true : serviceLive(j.tk);
    showSheet(context, j == null ? 'Add Service' : 'Edit Service', (ctx) => StatefulBuilder(builder: (ctx, set) {
          final staff = S.users.where((u) {
            final jt = (u['jobTypes'] as List?) ?? const [];
            return jt.isEmpty || jt.contains(type);
          }).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('1 · Name (required)'),
            TextField(controller: name, maxLength: 120),
            const FieldLabel('2 · Area'),
            TextField(controller: zone, decoration: const InputDecoration(hintText: 'e.g. Floors')),
            const FieldLabel('3 · Restaurants'),
            Wrap(children: [
              for (final l in kLocations)
                AppChip(l.code, locs.contains(l.id), () => set(() => locs.contains(l.id) ? locs.remove(l.id) : locs.add(l.id))),
            ]),
            Muted(locs.isEmpty ? 'No restaurants chosen — this job runs at all 8.' : 'The job runs only where it is ticked.', size: 12),
            const FieldLabel('4 · Assign users'),
            Wrap(children: [
              for (final u in staff)
                AppChip('${u['name']}', people.contains(u['id']),
                    () => set(() => people.contains(u['id']) ? people.remove(u['id']) : people.add('${u['id']}'))),
            ]),
            const Muted('Leave them all unticked for whoever is on shift.', size: 12),
            const FieldLabel('5 · Frequency'),
            ChipRow(const [('D', 'Daily'), ('W', 'Weekly'), ('M', 'Monthly')], freq, (v) => set(() => freq = v)),
            if (freq == 'W') ...[
              const FieldLabel('6 · Schedule'),
              DropdownButtonFormField<int?>(
                initialValue: day,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Spread across the week')),
                  for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text('Every ${kDayNames[i]}')),
                ],
                onChanged: (v) => set(() => day = v),
              ),
            ],
            const FieldLabel('7 · Time (optional)'),
            GestureDetector(
              onTap: () async {
                final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                if (tm != null) set(() => atTime = '${pad2(tm.hour)}:${pad2(tm.minute)}');
              },
              child: _box(atTime ?? '—', () => set(() => atTime = null)),
            ),
            const FieldLabel('8 · End date (optional)'),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: today(), firstDate: today(), lastDate: DateTime(2035));
                if (d != null) set(() => endDate = ymd(d));
              },
              child: _box(endDate == null ? '—' : fmtD(endDate), () => set(() => endDate = null)),
            ),
            const Muted('After this date the job stops being scheduled.', size: 12),
            const FieldLabel('Status'),
            DropdownButtonFormField<bool>(
              initialValue: enabled,
              items: const [
                DropdownMenuItem(value: true, child: Text('Active — scheduled')),
                DropdownMenuItem(value: false, child: Text('Off — not scheduled')),
              ],
              onChanged: (v) => set(() => enabled = v!),
            ),
            const SizedBox(height: 16),
            Btn(j == null ? 'Save Job' : 'Save Changes', () async {
              if (name.text.trim().isEmpty) return toast('Enter a job name');
              final body = {
                'name': name.text.trim(),
                'zone': zone.text.trim().isEmpty ? '${S.jobTypes.where((x) => x['id'] == type).firstOrNull?['name'] ?? 'Other'}' : zone.text.trim(),
                'freq': freq,
                'day': freq == 'W' ? day : null,
                'locs': locs.toList(),
                'assignees': people.toList(),
                'atTime': atTime,
                'endDate': endDate,
                'jobType': type,
                'enabled': enabled,
              };
              if (j == null) {
                try {
                  final r = await Api.I.post('/api/checklist/items', body);
                  final it = Map<String, dynamic>.from(r['item'] as Map);
                  S.checklist[it['tkey'] as String] = it;
                  S.save();
                  ensureJobs();
                  S.logAct('clean', 'Repeating job added: ${name.text.trim()}');
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast('“${name.text.trim()}” added');
                  setState(() {});
                } on ApiException catch (e) {
                  toast(e.isOffline ? 'You are offline — adding a job needs a connection' : e.message);
                }
              } else {
                if (ctx.mounted) Navigator.pop(ctx);
                await _patch(j.tk, body, 'Service updated');
              }
            }, kind: BtnKind.ok),
            if (j != null) ...[
              const SizedBox(height: 10),
              Btn('✕ Delete', () async {
                if (!await askConfirm(ctx, 'Delete ${j.name}?',
                    'It stops being scheduled at every kitchen. Cleaning already recorded against it keeps its photos and approvals.', 'Delete',
                    danger: true)) {
                  return;
                }
                try {
                  final b = builtinByTk(j.tk);
                  final r = await Api.I.delete('/api/checklist/items/${j.tk}', query: {if (b != null) 'builtInName': b.t.area});
                  S.checklist[j.tk] = Map<String, dynamic>.from(r['item'] as Map);
                  S.save();
                  S.logAct('clean', 'Cleaning deleted: "${j.name}"');
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() {});
                } on ApiException catch (e) {
                  toast(e.message);
                }
              }, kind: BtnKind.no),
            ],
          ]);
        }));
  }

  Widget _box(String text, VoidCallback clear) => Container(
        height: 52,
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: C.line, width: 1.5)),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (text != '—') IconButton(icon: const Icon(Icons.close, size: 18), onPressed: clear),
        ]),
      );
}
