import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/photo.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'manage.dart';
import 'shell.dart';

Widget statusPill(Rec t) {
  if (t['status'] == 'rejected') return const Pill('REJECTED', PillTone.red);
  if (t['status'] == 'completed') {
    return t['approved'] == true ? const Pill('DONE', PillTone.grn) : const Pill('PENDING APPROVAL', PillTone.blu);
  }
  return jobOverdue(t) ? const Pill('OVERDUE', PillTone.org) : const Pill('PENDING', PillTone.gry);
}

String assigneesShort(Rec t) {
  final a = assigneesOf(t);
  if (a.isEmpty) return 'Anyone on shift';
  final names = a.map((id) => uname(id).split(' ').first).toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.first} +${names.length - 1}';
}

String? decisionLine(Rec t) {
  if (t['status'] == 'rejected') {
    final r = (t['reject'] ?? '') as String;
    return 'Sent back by ${uname(t['approvedBy'] as String?)} · ${fmtDT((t['approvedAt'] as num?)?.toInt())}${r.isEmpty ? '' : ' — $r'}';
  }
  if (t['status'] == 'completed' && t['approved'] == true) {
    return 'Approved by ${uname(t['approvedBy'] as String?)} · ${fmtDT((t['approvedAt'] as num?)?.toInt())}';
  }
  if (t['status'] == 'completed') {
    return 'Sent in by ${uname((t['completedBy'] ?? t['assigned']) as String?)} · ${fmtDT((t['completedAt'] as num?)?.toInt())} — waiting on the Super Admin';
  }
  return null;
}

class TaskRow extends StatelessWidget {
  final Rec t;
  const TaskRow(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    final photo = (t['after'] ?? t['before']) as String?;
    final day = fixedDay(t);
    final dl = decisionLine(t);
    return LRow(
      leading: photo != null ? Photo(photo, width: 46, height: 46) : const Tile('🧽', Color(0xFFE8F0FB)),
      title: cleanName(t),
      sub: [
        t['zone'] ?? '',
        assigneesShort(t),
        fmtD(t['due'] as String?),
        if (t['time'] != null) t['time'],
      ].where((x) => '$x'.isNotEmpty).join(' · '),
      pills: [
        statusPill(t),
        if (t['freq'] == 'M') const Pill('MONTHLY', PillTone.blu),
        if (t['freq'] == 'W' && day != null) Pill('EVERY ${kDayNames[day].toUpperCase()}', PillTone.vio),
        if (missingPhoto(t)) const Pill('NO PHOTO', PillTone.org),
      ],
      extra: dl == null
          ? null
          : Text(dl, style: TextStyle(fontSize: 12, color: t['status'] == 'rejected' ? C.red : C.mut)),
      onTap: () => taskSheet(context, t['id'] as String),
    );
  }
}

class CleaningScreen extends StatefulWidget {
  const CleaningScreen({super.key});
  @override
  State<CleaningScreen> createState() => _CleaningScreenState();
}

class _CleaningScreenState extends State<CleaningScreen> {
  late String from, to;
  String range = 'week';

  @override
  void initState() {
    super.initState();
    _setRange('week');
  }

  void _setRange(String r) {
    final t = today();
    final mon = mondayOf(t);
    range = r;
    switch (r) {
      case 'last':
        from = ymd(addDays(mon, -7));
        to = ymd(addDays(mon, -1));
      case '7d':
        from = ymd(addDays(t, -6));
        to = ymd(t);
      default:
        from = ymd(mon);
        to = ymd(addDays(mon, 6));
    }
  }

  Future<void> _pick(bool isFrom) async {
    final cur = parseD(isFrom ? from : to);
    final d = await showDatePicker(
        context: context, initialDate: cur.isAfter(today()) ? today() : cur, firstDate: DateTime(2024), lastDate: today());
    if (d == null) return;
    setState(() {
      range = 'custom';
      if (isFrom) {
        from = ymd(d);
      } else {
        to = ymd(d);
      }
      if (from.compareTo(to) > 0) {
        final x = from;
        from = to;
        to = x;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final nav = context.watch<Nav>();
    final loc = S.loc;
    final f = nav.cleanFilter;
    final all = tasksInRange(loc, from, to);
    final st = statsOf(all);
    final wk = statsOf(all.where((t) => t['freq'] == 'W'));
    final mo = statsOf(all.where((t) => t['freq'] == 'M'));

    // Tuesday jobs: whole Monday–Sunday weeks the range touches.
    final tFrom = ymd(mondayOf(parseD(from))), tTo = ymd(addDays(mondayOf(parseD(to)), 6));
    final tues = tasksInRange(loc, tFrom, tTo).where(isTuesdayJob).toList();

    bool matchK(Rec t, String k) => switch (k) {
          'weekly' => t['freq'] == 'W',
          'monthly' => t['freq'] == 'M',
          'tuesday' => isTuesdayJob(t),
          'pending' => t['status'] == 'pending',
          'approve' => t['status'] == 'completed' && t['approved'] != true,
          'rejected' => t['status'] == 'rejected',
          'nophoto' => missingPhoto(t),
          'done' => t['status'] == 'completed' && t['approved'] == true,
          'mine' => isMine(t),
          _ => !isTuesdayJob(t),
        };
    bool match(Rec t) => matchK(t, f);
    int count(String k) => all.where((t) => matchK(t, k)).length;

    final shown = all.where(match).toList()..sort((a, b) => '${a['due']}'.compareTo('${b['due']}'));
    final zones = <String, List<Rec>>{};
    for (final t in shown) {
      zones.putIfAbsent((t['zone'] ?? 'Other') as String, () => []).add(t);
    }
    final chips = [
      if (S.me?['role'] == 'staff') ('mine', 'My jobs'),
      ('all', 'All ${all.length}'),
      ('weekly', 'Weekly ${count('weekly')}'),
      ('monthly', 'Monthly ${count('monthly')}'),
      ('tuesday', 'Tuesday ${tues.length}'),
      ('pending', 'Pending ${count('pending')}'),
      ('approve', 'To approve ${count('approve')}'),
      ('rejected', 'Rejected ${count('rejected')}'),
      ('nophoto', 'No photo ${count('nophoto')}'),
      ('done', 'Done ${count('done')}'),
    ];

    return Column(children: [
      PageHeader('FULL KITCHEN DEEP CLEAN', sub: locName(loc), allowAll: false),
      Expanded(
        child: PageBody(children: [
          AppCard(
            child: Row(children: [
              Ring(st.pct),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Cleaning compliance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${st.approved} of ${st.total} jobs done & approved'),
                  Muted('${st.pending} pending · ${st.rejected} rejected · ${st.noPhoto} missing photos'),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Stat('${wk.pct}%', 'Weekly · ${wk.total} jobs',
                    color: scoreColor(wk.pct), onTap: () => setState(() => nav.cleanFilter = 'weekly'))),
            const SizedBox(width: 8),
            Expanded(
                child: Stat('${mo.pct}%', 'Monthly · ${mo.total} jobs',
                    color: scoreColor(mo.pct), onTap: () => setState(() => nav.cleanFilter = 'monthly'))),
          ]),
          const SizedBox(height: 12),
          ChipRow(const [('week', 'This week'), ('last', 'Last week'), ('7d', 'Last 7 days')], range,
              (r) => setState(() => _setRange(r))),
          Row(children: [
            Expanded(child: _DateBox('From', from, () => _pick(true))),
            const SizedBox(width: 8),
            Expanded(child: _DateBox('To', to, () => _pick(false))),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Muted('Showing jobs due ${fmtD(from)} – ${fmtD(to)}'),
          ),
          if (tues.isNotEmpty || f == 'all') ...[
            SecTitle('Every Tuesday · ${tues.length} job${tues.length == 1 ? '' : 's'}'),
            if (tues.isEmpty)
              const AppCard(child: Muted('None due in this week'))
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Muted(
                    '${tues.where((t) => t['status'] == 'completed').length} of ${tues.length} done · week of ${fmtD(tFrom)}'),
              ),
              RowsCard([for (final t in tues) TaskRow(t)]),
            ],
          ],
          const SizedBox(height: 14),
          ChipRow(chips, f, (k) => setState(() => nav.cleanFilter = k)),
          if (shown.isEmpty)
            const EmptyState('🧼', 'Nothing here')
          else
            for (final z in zones.entries) ...[
              SecTitle(z.key),
              RowsCard([for (final t in z.value) TaskRow(t)]),
            ],
        ]),
      ),
    ]);
  }
}

class _DateBox extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _DateBox(this.label, this.value, this.onTap);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(label),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: C.line, width: 1.5)),
            child: Row(children: [
              Expanded(child: Text(fmtD(value), style: const TextStyle(fontWeight: FontWeight.w600))),
              const Icon(Icons.calendar_today_outlined, size: 18, color: C.mut),
            ]),
          ),
        ),
      ]);
}

// ---------------------------------------------------------------------------
// Job detail
// ---------------------------------------------------------------------------
void taskSheet(BuildContext context, String id) {
  showSheet(context, 'Cleaning task', (ctx) => _TaskDetail(id));
}

class _TaskDetail extends StatefulWidget {
  final String id;
  const _TaskDetail(this.id);
  @override
  State<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<_TaskDetail> {
  bool _busy = false;

  Future<void> _shoot(Rec t, bool camera) async {
    setState(() => _busy = true);
    try {
      final bytes = await PhotoTool.capture(
          stamp: '${fmtDT(DateTime.now().millisecondsSinceEpoch)}  ·  ${initials(S.me?['name'] as String?)}', camera: camera);
      if (bytes == null) return;
      t['before'] = Store.toDataUrl(bytes);
      S.touch('tasks', t);
      S.logAct('photo', 'photo added: ${cleanName(t)}', t['loc'] as String?);
      toast('Photo saved');
      final url = await S.storePhoto(bytes, t['loc'] as String);
      if (!url.startsWith('data:') && S.tasks[t['id']]?['before'] == t['before']) {
        t['before'] = url;
        S.touch('tasks', t);
      }
    } catch (_) {
      toast('That photo could not be read — try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send(Rec t) {
    if (t['before'] == null && t['after'] == null) return toast('A photo is compulsory');
    t
      ..['status'] = 'completed'
      ..['completedAt'] = DateTime.now().millisecondsSinceEpoch
      ..['completedBy'] = S.myId
      ..['approved'] = null
      ..['reject'] = '';
    S.touch('tasks', t);
    S.logAct('clean', 'Completed: ${cleanName(t)}', t['loc'] as String?);
    toast('Sent to the Super Admin');
    Navigator.pop(context);
  }

  void _reopen(Rec t) {
    t
      ..['status'] = 'pending'
      ..['approved'] = null
      ..['approvedBy'] = null
      ..['approvedAt'] = null
      ..['reject'] = ''
      ..['completedAt'] = null;
    S.touch('tasks', t);
    toast('Task re-opened');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final t = S.tasks[widget.id];
    if (t == null) return const EmptyState('🧽', 'This job is no longer here');
    final p = S.perm;
    final can = canDoTask(t);
    final editPhoto = can && (p.approve || t['approved'] != true);
    final photo = (t['after'] ?? t['before']) as String?;
    final day = fixedDay(t);
    final kind = t['freq'] == 'M'
        ? 'Monthly heavy job'
        : (t['freq'] == 'D' ? 'Daily job' : (day != null ? 'Weekly job · every ${kDayNames[day]}' : 'Weekly job'));
    final j = jobFor(tkeyOf(t));
    final deleted = S.checklist[tkeyOf(t)]?['deleted'] == true;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cleanName(t), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (deleted)
            const Text('This cleaning job has been deleted — kept for the record', style: TextStyle(color: C.red, fontSize: 12.5))
          else if (j != null && S.checklist[j.tk]?['prevName'] != null)
            Muted('Renamed · was “${S.checklist[j.tk]!['prevName']}”', size: 12),
          const SizedBox(height: 4),
          Muted('${t['zone'] ?? ''} · $kind · ${locName(t['loc'] as String?)}'),
          const SizedBox(height: 8),
          statusPill(t),
          const Divider(height: 22),
          KV.text('Assigned to', assigneesShort(t)),
          KV.text('Due date', '${fmtD(t['due'] as String?)}${t['time'] != null ? ' · ${t['time']}' : ''}'),
          KV.text('Done by', uname(t['completedBy'] as String?)),
          KV.text('Completed', fmtDT((t['completedAt'] as num?)?.toInt())),
        ]),
      ),
      if (t['status'] == 'rejected') ...[
        const SizedBox(height: 10),
        InfoCard.red(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rejected — ${uname(t['approvedBy'] as String?)} · ${fmtDT((t['approvedAt'] as num?)?.toInt())}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${t['reject'] ?? ''}'),
        ])),
      ],
      if (t['approved'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('✓ Approved by ${uname(t['approvedBy'] as String?)} · ${fmtDT((t['approvedAt'] as num?)?.toInt())}',
              style: const TextStyle(color: C.grn, fontWeight: FontWeight.w800)),
        ),
      const SecTitle('Photo — compulsory'),
      if (photo == null)
        GestureDetector(
          onTap: editPhoto && !_busy ? () => _shoot(t, true) : null,
          child: Container(
            height: 170,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.chev, width: 2, style: BorderStyle.solid),
            ),
            child: _busy
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('📷', style: TextStyle(fontSize: 38)),
                    const SizedBox(height: 6),
                    Text(editPhoto ? 'TAP TO TAKE PHOTO' : 'NOT UPLOADED',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: C.mut, letterSpacing: .5)),
                  ]),
          ),
        )
      else
        Stack(children: [
          GestureDetector(
            onTap: () => showPhotoViewer(context, photo),
            child: Container(
              height: 260,
              decoration: BoxDecoration(color: const Color(0xFF101413), borderRadius: BorderRadius.circular(16)),
              child: Photo(photo, fit: BoxFit.contain, radius: 16),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(Store.isDataUrl(photo) ? 'ON THIS PHONE · UPLOADING' : 'TAP TO ENLARGE',
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ),
          if (editPhoto && t['status'] != 'completed')
            Positioned(
              right: 8,
              top: 8,
              child: Row(children: [
                _round(Icons.refresh, () => _shoot(t, true)),
                const SizedBox(width: 6),
                _round(Icons.close, () {
                  t['before'] = null;
                  t['after'] = null;
                  S.touch('tasks', t);
                }),
              ]),
            ),
        ]),
      if (editPhoto && photo == null && !_busy)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Btn('🖼 Upload from gallery', () => _shoot(t, false), kind: BtnKind.sec, small: true),
        ),
      const SizedBox(height: 14),
      if (can && t['status'] != 'completed') ...[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${photo != null ? '✓' : '1'}  Take a photo',
                style: TextStyle(fontWeight: FontWeight.w700, color: photo != null ? C.grn : C.ink)),
            const SizedBox(height: 6),
            const Text('2  Tap Send — it goes to the Super Admin', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 10),
        photo != null
            ? Btn('➤ Send', () => _send(t), kind: BtnKind.ok)
            : Btn('📷 Add a photo first', () => toast('Take a photo first'), kind: BtnKind.sec),
      ],
      if (t['status'] == 'completed' && t['approved'] != true)
        p.approve
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const InfoCard.blue(Text('Waiting for review · approve or reject it here or in Task Review')),
                Row(children: [
                  Expanded(child: Btn('✓ Approve', () {
                    approveTask(t);
                    Navigator.pop(context);
                  }, kind: BtnKind.ok)),
                  const SizedBox(width: 10),
                  Expanded(child: Btn('✕ Reject', () async {
                    if (await rejectTask(context, t) && context.mounted) Navigator.pop(context);
                  }, kind: BtnKind.no)),
                ]),
              ])
            : const InfoCard.blue(Text('Sent to the Super Admin · waiting for approval')),
      if (p.approve && t['status'] != 'pending') ...[
        const SizedBox(height: 10),
        Btn('↺ Re-open task', () => _reopen(t), kind: BtnKind.sec),
      ],
      if (p.superadmin) ...[
        const SizedBox(height: 10),
        Btn('🗑 Delete cleaning', () async {
          if (!await askConfirm(context, 'Delete this job?', 'This removes “${cleanName(t)}” for this period.', 'Delete',
              danger: true)) {
            return;
          }
          S.remove('tasks', t);
          S.logAct('clean', 'Cleaning deleted: "${cleanName(t)}"', t['loc'] as String?);
          if (context.mounted) Navigator.pop(context);
        }, kind: BtnKind.no),
      ],
    ]);
  }

  Widget _round(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(i, color: Colors.white, size: 20),
        ),
      );
}
