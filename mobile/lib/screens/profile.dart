import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'auth_screens.dart';
import 'cleaning.dart';
import 'expiry.dart';
import 'shell.dart';

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
class AlertRow extends StatelessWidget {
  final Alert a;
  final VoidCallback? onOpened;
  const AlertRow(this.a, {super.key, this.onOpened});
  @override
  Widget build(BuildContext context) {
    final unread = !S.read.containsKey(a.id);
    return InkWell(
      onTap: () {
        S.read[a.id] = 1;
        S.save();
        onOpened?.call();
        if (a.goKind == 'task') {
          taskSheet(context, a.goId);
        } else if (a.goKind == 'product') {
          productSheet(context, a.goId);
        } else {
          navState.go('chk');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: sevColor(a.sev), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text.rich(TextSpan(children: [
                TextSpan(text: a.type, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' · ${locName(a.loc)}'),
              ]), style: const TextStyle(fontSize: 12.5)),
              Text(a.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.mut)),
            ]),
          ),
          if (unread) Container(width: 9, height: 9, decoration: const BoxDecoration(color: C.blue, shape: BoxShape.circle)),
        ]),
      ),
    );
  }
}

void alertsSheet(BuildContext context) {
  final alerts = buildAlerts();
  showSheet(context, 'Notifications (${alerts.length})', (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (alerts.isEmpty)
        const EmptyState('✅', 'No open alerts')
      else ...[
        RowsCard([for (final a in alerts.take(200)) AlertRow(a, onOpened: () => Navigator.pop(ctx))]),
        const SizedBox(height: 12),
        Btn('Mark all as read', () {
          for (final a in alerts) {
            S.read[a.id] = 1;
          }
          S.save();
          Navigator.pop(ctx);
        }, kind: BtnKind.sec),
      ],
    ]);
  });
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------
List<String> permissionsFor(String role, String? loc) => switch (role) {
      'superadmin' => [
          'Full access to all 8 locations',
          'Approve or reject new sign-ups — only you can',
          'Approve / reject any cleaning task',
          'Create users & reset passwords',
        ],
      'exec' || 'aexec' || 'admin' => ['Full access to all 8 locations', 'Record and send cleaning work for approval', 'View the audit log'],
      'hok' => ['View all 8 locations', 'Monitor compliance live', 'Record and send cleaning work for approval'],
      'manager' => [
          'Access to ${locName(loc)} only',
          'Record and send cleaning work for approval',
          'Check expiry & labelling',
          'Add products & labels',
        ],
      'auditor' => ['Read-only across all 8 locations', 'View photo evidence'],
      _ => ['Complete assigned tasks', 'Upload photo evidence', 'Add products & check expiry', 'Write product labels'],
    };

void meSheet(BuildContext context) {
  showSheet(context, 'Signed in', (ctx) {
    final me = S.me ?? {};
    final p = S.perm;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: C.btnGradient, borderRadius: BorderRadius.circular(16)),
            child: Text(initials(me['name'] as String?),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${me['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Muted('${p.label} · ${me['loc'] == null ? 'All locations' : locName(me['loc'] as String?)}'),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Login ID '),
                TextSpan(text: '${me['uid']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]), style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ]),
      ),
      const SecTitle('Your permissions'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in permissionsFor('${me['role']}', me['loc'] as String?))
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('✓  $s')),
        ]),
      ),
      const SizedBox(height: 14),
      Btn('🔒 Change my password', () => changePwSheet(ctx), kind: BtnKind.sec),
      const SizedBox(height: 8),
      Btn('☁️ Cloud sync — ${S.syncLabel}', () => syncSheet(ctx), kind: BtnKind.sec),
      if (p.manage) ...[const SizedBox(height: 8), Btn('🕘 Audit log', () => activitySheet(ctx), kind: BtnKind.sec)],
      const SizedBox(height: 8),
      Btn('❓ How to use the app', () => helpSheet(ctx), kind: BtnKind.sec),
      const SizedBox(height: 8),
      Btn('ℹ️ About & version', () => aboutSheet(ctx), kind: BtnKind.sec),
      const SecTitle('Account'),
      Btn('Log out', () async {
        if (!await askConfirm(ctx, 'Log out?', 'You will need your ID and password to get back in.', 'Log out', danger: true)) return;
        if (ctx.mounted) Navigator.pop(ctx);
        if (context.mounted) signOutFrom(context);
      }, kind: BtnKind.no),
      const SizedBox(height: 8),
      const Center(child: Muted('You stay signed in on this phone until you log out.', size: 12)),
    ]);
  });
}

void changePwSheet(BuildContext context) {
  final cur = TextEditingController(), pw = TextEditingController(), pw2 = TextEditingController();
  showSheet(context, 'Change your password', (ctx) {
    var busy = false;
    String? err;
    return StatefulBuilder(builder: (ctx, set) {
      Future<void> save() async {
        final e = passwordProblem(pw.text, pw2.text);
        if (e != null) return set(() => err = e);
        set(() => busy = true);
        try {
          final r = await Api.I.post('/api/auth/change-password',
              {'currentPassword': cur.text, 'newPassword': pw.text, 'confirmPassword': pw2.text});
          await S.adoptUser(Map<String, dynamic>.from(r['user'] as Map));
          S.logAct('user', 'Password changed');
          if (ctx.mounted) Navigator.pop(ctx);
          toast('Password updated');
        } on ApiException catch (x) {
          set(() {
            err = x.message;
            busy = false;
          });
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InfoCard.blue(Text.rich(TextSpan(children: [
          const TextSpan(text: 'Your ID is '),
          TextSpan(text: '${S.me?['uid']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: '. It cannot be changed.'),
        ]))),
        if (err != null) InfoCard.red(Text(err!)),
        const FieldLabel('Current password'),
        TextField(controller: cur, obscureText: true),
        const FieldLabel('New password'),
        TextField(controller: pw, obscureText: true, decoration: InputDecoration(hintText: 'At least ${S.minPasswordLength} characters')),
        const FieldLabel('Type it again'),
        TextField(controller: pw2, obscureText: true),
        const SizedBox(height: 16),
        Btn('Save new password', save, busy: busy),
      ]);
    });
  });
}

void syncSheet(BuildContext context) {
  showSheet(context, 'Cloud sync', (ctx) => Consumer<Store>(builder: (ctx, s, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.syncLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (s.syncError != null) Text(s.syncError!, style: const TextStyle(color: C.red)),
              const SizedBox(height: 6),
              Muted('Server: ${Api.I.base}'),
              Muted('Last sync: ${s.lastSync == null ? '—' : fmtDT(s.lastSync!.millisecondsSinceEpoch)}'),
              Muted('${s.tasks.length} jobs · ${s.products.length} products on this phone'),
            ]),
          ),
          const SizedBox(height: 12),
          const Muted('Changes upload about a second after you make them. Other phones\' changes download every 45 seconds, when the app is reopened and when the internet comes back.'),
          const SizedBox(height: 12),
          Btn('↻ Sync now', s.syncState == 'syncing' ? null : () => s.sync()),
        ]);
      }));
}

void helpSheet(BuildContext context) {
  final staffish = ['staff', 'manager'].contains(S.me?['role']);
  final items = staffish
      ? const [
          ('🧽', 'Do a cleaning job', 'Tap CLEANING, pick a job, clean the area, take a photo, then tap Send. The Super Admin approves it.'),
          ('📷', 'A photo is compulsory', 'The Send button only appears once a photo is taken. No photo, no record.'),
          ('🏷️', 'Label a product', 'Tap LABEL A PRODUCT, fill in the name and dates, add a photo, save. Copy the label onto a sticker and put it on the container.'),
          ('📅', 'Check expiry', 'Red means throw it away today. Orange means use it within a week. Check this at the start of every shift.'),
          ('📋', 'Daily checklists', 'Lunch, Dinner and Closing checklists open only in their time window. Tick what you did and submit.'),
        ]
      : const [
          ('📊', 'Your dashboard', 'One score per location out of 100: 40% cleaning, 35% expiry control, 25% labelling. Tap any location for the detail.'),
          ('✅', 'Approvals', 'Cleaning jobs come to the Super Admin with photo evidence. Approve, or reject with a reason and it goes back to the team.'),
          ('🔔', 'Alerts', 'The bell shows overdue jobs, missing photos, expired stock and missing labels across every kitchen.'),
          ('👥', 'People', 'Create users, change roles, reset forgotten passwords.'),
        ];
  showSheet(context, 'How to use the app', (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RowsCard([for (final (e, t, d) in items) LRow(leading: Tile(e, const Color(0xFFEEF2FF)), title: t, sub: d)]),
        const SizedBox(height: 12),
        const InfoCard(Text(
            'Kitchens run on electric equipment only — never spray water near plug points, switches or cables. Wipe those dry.')),
      ]));
}

void aboutSheet(BuildContext context) {
  showSheet(context, 'About', (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Center(child: Text('🍳', style: TextStyle(fontSize: 44))),
        const Center(child: Text('Bookends Cleaning', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        const Center(child: Muted('Version 1.0 · mobile app')),
        const SizedBox(height: 14),
        AppCard(
          child: Column(children: [
            KV.text('Locations', '${kLocations.length}'),
            KV.text('Cleaning jobs', '${S.tasks.length}'),
            KV.text('People', '${S.users.length}'),
            KV.text('Products tracked', '${S.products.length}'),
            KV.text('Cloud sync', S.syncLabel),
            KV.text('Server', Api.I.base),
          ]),
        ),
        if (S.perm.manage) ...[
          const SecTitle('Danger zone'),
          Btn('Reset this device', () async {
            if (!await askConfirm(ctx, 'Reset this device?',
                'This clears the copy kept on this phone and downloads everything again. Work not yet uploaded is lost.', 'Reset',
                danger: true)) {
              return;
            }
            await S.wipeLocal();
            S.sync();
            if (ctx.mounted) Navigator.pop(ctx);
            toast('Device reset — downloading');
          }, kind: BtnKind.no),
        ],
      ]));
}

const _logTypes = {
  'user': 'Users',
  'clean': 'Cleaning',
  'product': 'Products',
  'photo': 'Photos',
  'reject': 'Rejected',
  'label': 'Labels',
  'approve': 'Approved',
  'checklist': 'Checklists',
};

void activitySheet(BuildContext context) {
  showSheet(context, 'Audit log', (ctx) {
    var q = '', type = 'all';
    return StatefulBuilder(builder: (ctx, set) {
      String lbl(String t) => _logTypes[t] ?? t;
      final all = S.log;
      final shown = all.where((e) {
        if (type != 'all' && e['type'] != type) return false;
        if (q.isEmpty) return true;
        return '${e['text']} ${uname(e['by'] as String?)} ${locName(e['loc'] as String?)} ${lbl('${e['type']}')}'
            .toLowerCase()
            .contains(q.toLowerCase());
      }).toList();
      final counts = <String, int>{};
      for (final e in all) {
        counts['${e['type']}'] = (counts['${e['type']}'] ?? 0) + 1;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Muted(
            'Everything this device has recorded for the last 30 days: what changed, who changed it, which kitchen, and when. Older entries are removed automatically.'),
        const FieldLabel('Search'),
        TextField(
            decoration: const InputDecoration(hintText: 'Name, kitchen or what changed'), onChanged: (v) => set(() => q = v)),
        const SizedBox(height: 10),
        ChipRow([
          ('all', 'All ${all.length}'),
          for (final k in counts.keys) (k, '${lbl(k)} ${counts[k]}'),
        ], type, (k) => set(() => type = k)),
        Muted(shown.length == all.length ? '${all.length} entr${all.length == 1 ? 'y' : 'ies'}' : '${shown.length} of ${all.length}'),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          EmptyState('🕘', q.isNotEmpty || type != 'all' ? 'Nothing matches' : 'Nothing recorded yet')
        else
          RowsCard([
            for (final e in shown.take(300))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${e['text']}', style: const TextStyle(fontSize: 13.5))),
                    Pill(lbl('${e['type']}'), PillTone.gry),
                  ]),
                  Muted(
                      '${e['by'] == null ? 'System' : uname(e['by'] as String?)} · ${e['loc'] == null ? 'all kitchens' : locName(e['loc'] as String?)} · ${fmtD(ymd(DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt())))} ${fmtClock((e['t'] as num).toInt())}',
                      size: 12),
                ]),
              ),
          ]),
      ]);
    });
  });
}
