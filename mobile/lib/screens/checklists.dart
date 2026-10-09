import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/daily_checklist.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'shell.dart';

/// Lunch / Dinner / Closing. The server's clock decides what is open.
class Ck extends ChangeNotifier {
  Ck._();
  static final Ck I = Ck._();

  List<Rec> windows = [];
  int skew = 0; // serverNow - local now
  DateTime? loadedAt;
  String? error;
  bool loading = false;
  Timer? _tick;
  final Set<String> _reminded = {};

  int get now => DateTime.now().millisecondsSinceEpoch + skew;

  Future<void> load({bool force = false}) async {
    if (loading) return;
    if (!force && loadedAt != null && DateTime.now().difference(loadedAt!).inSeconds < 60) return;
    loading = true;
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final r = await Api.I.get('/api/checklists/status');
      final t1 = DateTime.now().millisecondsSinceEpoch;
      skew = ((r['serverNow'] as num).toInt()) - ((t0 + t1) ~/ 2);
      windows = ((r['windows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      loadedAt = DateTime.now();
      error = null;
    } on ApiException catch (e) {
      error = e.isOffline ? 'offline' : e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Ticks every 15 s: re-renders countdowns, reloads when a window flips,
  /// and raises the 5-minute reminders as bell alerts.
  void startTicker() {
    _tick ??= Timer.periodic(const Duration(seconds: 15), (_) => _onTick());
    _onTick();
  }

  void _onTick() {
    if (S.me == null) return;
    for (final w in windows) {
      final open = w['open'] == true;
      final ends = (w['endsAt'] as num?)?.toInt();
      final next = (w['nextOpensAt'] as num?)?.toInt();
      if ((open && ends != null && now >= ends) || (!open && next != null && now >= next)) {
        load(force: true);
        break;
      }
    }
    _buildReminders();
    notifyListeners();
  }

  void _buildReminders() {
    final out = <Alert>[];
    if (S.perm.readonly || !tabAllowed('chk')) {
      checklistReminders = out;
      return;
    }
    const five = 5 * 60000;
    final kitchen = S.loc == 'ALL' ? 'your kitchen' : locName(S.loc);
    for (final w in windows) {
      final label = w['label'] as String;
      final win = kChecklistWindows.firstWhere((x) => x.type == w['type']);
      final next = (w['nextOpensAt'] as num?)?.toInt();
      final ends = (w['endsAt'] as num?)?.toInt();
      if (w['open'] != true && next != null && now >= next - five && now < next) {
        final m = ((next - now) / 60000).ceil();
        final key = '${w['type']}|open|$next';
        out.add(Alert('ck$key', 3, 'Checklist opening', S.loc, '$label opens in $m minute${m == 1 ? '' : 's'}',
            'Open from ${rangeLabel(win)} IST. $kitchen.', 'chk', ''));
        _notify(key, '$label opens in $m minute${m == 1 ? '' : 's'}');
      }
      if (w['open'] == true && ends != null && now >= ends - five && now < ends && !sentHere(w)) {
        final m = ((ends - now) / 60000).ceil();
        final key = '${w['type']}|close|$ends';
        out.add(Alert('ck$key', 3, 'Checklist closing', S.loc, '$label closes in $m minute${m == 1 ? '' : 's'}',
            'Not sent yet for $kitchen — closes at ${fmtIstTime(ends)} IST.', 'chk', ''));
        _notify(key, '$label closes in $m minute${m == 1 ? '' : 's'}');
      }
    }
    checklistReminders = out;
  }

  void _notify(String key, String title) {
    if (_reminded.add(key)) toast('🔔 $title');
  }

  List<Rec> subs(Rec w) => ((w['submissions'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Has the kitchen being looked at already sent this checklist?
  bool sentHere(Rec w) {
    final s = subs(w);
    if (S.loc == 'ALL') return s.isNotEmpty;
    return s.any((m) => m['loc'] == S.loc) || (w['submission'] != null && S.me?['loc'] == S.loc);
  }

  Rec? subHere(Rec w) {
    final s = subs(w);
    for (final m in s) {
      if (S.loc == 'ALL' || m['loc'] == S.loc) return m;
    }
    final mine = w['submission'];
    return mine == null ? null : Map<String, dynamic>.from(mine as Map);
  }
}

const _ckStyle = {
  'LUNCH': ('🍽️', Color(0xFFFFF7E2), 'Lunch'),
  'DINNER': ('🌆', Color(0xFFFDE9E4), 'Dinner'),
  'CLOSING': ('🌙', Color(0xFFEEF2FF), 'Closing'),
};

String _until(int ms) {
  final m = (ms / 60000).ceil();
  if (m < 60) return '$m min';
  return '${m ~/ 60}h ${m % 60}m';
}

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  String range = '7d';
  List<Rec>? records;
  String? recErr;

  @override
  void initState() {
    super.initState();
    Ck.I.load(force: true);
    Ck.I.startTicker();
    _loadRecords();
  }

  /* Everyone sees records: Admin EXE every restaurant's, everyone else
     the ones they sent themselves (the server decides which). */
  bool get _mayList => S.me != null;

  (String, String) get _dates {
    final t = istYmd();
    final d = parseD(t);
    return switch (range) {
      'yesterday' => (ymd(addDays(d, -1)), ymd(addDays(d, -1))),
      '7d' => (ymd(addDays(d, -6)), t),
      _ => (t, t),
    };
  }

  Future<void> _loadRecords() async {
    if (!_mayList) return;
    final (f, t) = _dates;
    try {
      final r = await Api.I.get('/api/checklists', query: {'from': f, 'to': t});
      if (!mounted) return;
      setState(() {
        records = ((r['checklists'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        recErr = null;
      });
    } on ApiException catch (_) {
      if (mounted) setState(() => recErr = 'Could not load checklist records. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    return ListenableBuilder(
      listenable: Ck.I,
      builder: (context, _) {
        final ck = Ck.I;
        final nowMs = ck.now;
        return Column(children: [
          const PageHeader('DAILY CHECKLISTS', sub: 'Lunch · Dinner · Closing · IST'),
          Expanded(
            child: PageBody(
              onRefresh: () async {
                await ck.load(force: true);
                await _loadRecords();
              },
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Now '),
                  TextSpan(text: fmtIstTime(nowMs), style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' IST · ${fmtD(istYmd(DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true)))}'),
                ])),
                const SizedBox(height: 10),
                if (ck.error == 'offline')
                  const InfoCard(Text(
                      'No connection to the server. Times below use this device\'s clock. A connection is needed to submit a checklist.'))
                else if (ck.error != null)
                  InfoCard.red(Text(ck.error!)),
                if (ck.windows.isEmpty && ck.loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
                for (final w in ck.windows) _card(context, w, nowMs),
                const SizedBox(height: 4),
                const InfoCard.blue(Text(
                    '🔔 Reminders appear here and on the bell 5 minutes before each checklist opens and 5 minutes before it closes, while the app is open.')),
                const Muted('Each checklist opens only during its time window. Press Open Checklist, tick the items you have done and submit.'),
                if (_mayList) ..._records(context),
              ],
            ),
          ),
        ]);
      },
    );
  }

  Widget _card(BuildContext context, Rec w, int nowMs) {
    final type = w['type'] as String;
    final (emoji, bg, _) = _ckStyle[type]!;
    final win = kChecklistWindows.firstWhere((x) => x.type == type);
    final sub = Ck.I.subHere(w);
    final open = w['open'] == true;
    Widget status;
    if (sub != null) {
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Pill('SUBMITTED', PillTone.blu),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: 'Submitted at ${fmtIstTime((sub['submittedAt'] as num).toInt())}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' · shift of ${fmtD(sub['shiftDate'] as String?)}'),
        ])),
        Muted('${sub['ticked'] ?? '?'} of ${sub['total'] ?? kChecklistItemCount} items ticked${sub['userName'] != null ? ' · ${sub['userName']}' : ''}.'),
      ]);
    } else if (open) {
      final ends = (w['endsAt'] as num).toInt();
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Pill('AVAILABLE', PillTone.grn),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Available now', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' · closes at ${fmtIstTime(ends)} (in ${_until(ends - nowMs)})'),
        ])),
      ]);
    } else {
      final next = (w['nextOpensAt'] as num?)?.toInt();
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Pill('CLOSED', PillTone.gry),
        const SizedBox(height: 6),
        Text('${w['label']} is currently unavailable.'),
        Muted('Available from ${fmtMinutes(win.start)} to ${fmtMinutes(win.end)}.'),
        if (next != null) Muted('Opens in ${_until(next - nowMs)}'),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Tile(emoji, bg, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${w['label']}', style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                Text('${fmtMinutes(win.start)} – ${fmtMinutes(win.end)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          status,
          const SizedBox(height: 10),
          Btn(sub != null ? 'View checklist' : 'Open Checklist', open || sub != null ? () => ckSheet(context, type) : null,
              small: true, kind: sub != null ? BtnKind.sec : BtnKind.primary),
        ]),
      ),
    );
  }

  List<Widget> _records(BuildContext context) {
    final (f, t) = _dates;
    final recs = records ?? [];
    final nowMs = Ck.I.now;
    // Fill in the gaps: every kitchen × checklist × shift with no record.
    final locs = S.perm.all ? (S.loc == 'ALL' ? kLocations.map((l) => l.id).toList() : [S.loc]) : [S.me?['loc'] as String? ?? ''];
    final rows = <(String date, String type, String loc, Rec? rec, String status)>[];
    for (var d = parseD(f); !d.isAfter(parseD(t)); d = addDays(d, 1)) {
      final dy = ymd(d);
      for (final win in kChecklistWindows) {
        final start = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch + (win.start - 330) * 60000;
        final endDay = win.overnight ? addDays(d, 1) : d;
        final end = DateTime.utc(endDay.year, endDay.month, endDay.day).millisecondsSinceEpoch + (win.end - 330) * 60000;
        for (final l in locs) {
          final rec = recs.where((r) => r['shiftDate'] == dy && r['type'] == win.type && r['loc'] == l).firstOrNull;
          if (rec != null) {
            rows.add((dy, win.type, l, rec, 'SUBMITTED'));
          } else if (nowMs >= end) {
            rows.add((dy, win.type, l, null, 'MISSED'));
          } else if (nowMs >= start) {
            rows.add((dy, win.type, l, null, 'AVAILABLE'));
          }
        }
      }
    }
    const order = {'LUNCH': 0, 'DINNER': 1, 'CLOSING': 2};
    rows.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      if (c != 0) return c;
      final o = order[a.$2]! - order[b.$2]!;
      return o != 0 ? o : locName(a.$3).compareTo(locName(b.$3));
    });
    final sent = rows.where((r) => r.$5 == 'SUBMITTED').length;
    final missed = rows.where((r) => r.$5 == 'MISSED').length;
    final openN = rows.where((r) => r.$5 == 'AVAILABLE').length;
    return [
      const SecTitle('Checklist records'),
      ChipRow(const [('today', 'Today'), ('yesterday', 'Yesterday'), ('7d', 'Last 7 days')], range, (k) {
        setState(() {
          range = k;
          records = null;
        });
        _loadRecords();
      }),
      StatGrid([
        Stat('$sent', 'Submitted', color: C.grn),
        Stat('$missed', 'Missed', color: missed > 0 ? C.red : C.mut),
        Stat('$openN', 'Open now', color: C.yel),
      ]),
      const SizedBox(height: 10),
      if (recErr != null)
        InfoCard.red(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(recErr!),
          TextButton(onPressed: _loadRecords, child: const Text('Try again')),
        ]))
      else if (records == null)
        const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
      else if (rows.isEmpty)
        const EmptyState('📋', 'No checklists yet for this period.')
      else
        RowsCard([
          for (final r in rows)
            LRow(
              leading: Tile(_ckStyle[r.$2]!.$1, _ckStyle[r.$2]!.$2, size: 40),
              title: '${_ckStyle[r.$2]!.$3} · ${locById(r.$3)?.name ?? r.$3}',
              sub: [
                fmtD(r.$1),
                if (r.$4 != null) '${r.$4!['userName']} · ${fmtIstTime((r.$4!['submittedAt'] as num).toInt())}',
              ].join(' · '),
              pills: [
                Pill(r.$5, r.$5 == 'SUBMITTED' ? PillTone.grn : (r.$5 == 'MISSED' ? PillTone.red : PillTone.yel)),
                if (r.$4 != null)
                  Pill('${r.$4!['ticked']}/${r.$4!['total']}',
                      r.$4!['ticked'] == r.$4!['total'] ? PillTone.grn : PillTone.org),
              ],
              onTap: r.$4 == null ? null : () => ckViewRecord(context, r.$4!['id'] as String),
            ),
        ]),
      const SizedBox(height: 8),
      const Muted(
          '“Submitted” means the user submitted the checklist in the app inside the time window. “Ticked” shows how many items they ticked; the rest were left not done. Tap a submitted row to see every item.',
          size: 12),
    ];
  }
}

// ---------------------------------------------------------------------------
// Fill in / view
// ---------------------------------------------------------------------------
void ckSheet(BuildContext context, String type) {
  final w = Ck.I.windows.firstWhere((x) => x['type'] == type);
  showSheet(context, '${w['label']}', (ctx) => _CkForm(type));
}

class _CkForm extends StatefulWidget {
  final String type;
  const _CkForm(this.type);
  @override
  State<_CkForm> createState() => _CkFormState();
}

class _CkFormState extends State<_CkForm> {
  late List<bool> ticks = List.filled(kChecklistItemCount, false);
  String? err;
  bool busy = false;
  Rec? done;

  Future<void> _submit() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final r = await Api.I.post('/api/checklists', {
        'type': widget.type,
        'loc': S.perm.all ? (S.loc == 'ALL' ? null : S.loc) : null,
        'answers': ticks,
      });
      done = Map<String, dynamic>.from(r['checklist'] as Map);
      final w = Ck.I.windows.firstWhere((x) => x['type'] == widget.type);
      S.logAct('checklist', '${w['label']} submitted', done!['loc'] as String?);
      toast('${w['label']} submitted');
      await Ck.I.load(force: true);
    } on ApiException catch (e) {
      if (e.code == 'ALREADY_SUBMITTED') {
        toast('This restaurant has already submitted this checklist for this shift');
        if (e.body['checklist'] != null) done = Map<String, dynamic>.from(e.body['checklist'] as Map);
        await Ck.I.load(force: true);
      } else if (e.isOffline) {
        err = 'Something went wrong. Please check your connection and try again.';
      } else {
        err = e.message;
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Ck.I,
      builder: (context, _) {
        final w = Ck.I.windows.firstWhere((x) => x['type'] == widget.type);
        final win = kChecklistWindows.firstWhere((x) => x.type == widget.type);
        final (emoji, _, _) = _ckStyle[widget.type]!;
        final sub = done ?? Ck.I.subHere(w);
        final hero = Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(gradient: C.headerGradient, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOU ARE COMPLETING',
                style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('$emoji ${w['label']}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${rangeLabel(win)} IST · shift of ${fmtD(w['shiftDate'] as String?)} · ${locName(S.loc)} · ${S.me?['name']}',
                style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12.5)),
          ]),
        );
        if (sub != null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            hero,
            InfoCard.blue(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✅ ${w['label']} completed', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${sub['ticked']} of ${sub['total']} items ticked by ${sub['userName']} at ${fmtIstTime((sub['submittedAt'] as num).toInt())} IST · shift of ${fmtD(sub['shiftDate'] as String?)}'),
            ])),
            if (sub['id'] != null) Btn('See every item', () => ckViewRecord(context, sub['id'] as String), kind: BtnKind.sec),
            const SizedBox(height: 10),
            Btn('Close', () => Navigator.pop(context)),
          ]);
        }
        if (w['open'] != true) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            hero,
            InfoCard.red(Text('${w['label']} is currently unavailable.\nAvailable from ${fmtMinutes(win.start)} to ${fmtMinutes(win.end)}.')),
            Btn('Close', () => Navigator.pop(context)),
          ]);
        }
        if (S.perm.readonly) {
          return Column(children: [hero, const InfoCard(Text('Read-only account — auditors cannot submit checklists.'))]);
        }
        if (S.perm.all && S.loc == 'ALL') {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            hero,
            const InfoCard(Text.rich(TextSpan(children: [
              TextSpan(text: 'Which kitchen is this for? ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: 'Choose the kitchen you are at from the location menu at the top of the page, then open the checklist again.'),
            ]))),
            Btn('Close', () => Navigator.pop(context)),
          ]);
        }
        var i = 0;
        final n = ticks.where((x) => x).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          hero,
          const Muted('Tick each item as you complete it. You can submit at any time; any item left unticked is recorded as not done.'),
          for (final (section, qs) in kChecklistSections) ...[
            SecTitle(section),
            RowsCard([
              for (final q in qs)
                Builder(builder: (_) {
                  final idx = i++;
                  return InkWell(
                    onTap: () => setState(() => ticks[idx] = !ticks[idx]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: ticks[idx] ? C.grn : Colors.white,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: ticks[idx] ? C.grn : const Color(0xFFB8C0DC), width: 2),
                          ),
                          child: ticks[idx] ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(q)),
                      ]),
                    ),
                  );
                }),
            ]),
          ],
          const SizedBox(height: 12),
          Muted('$n of $kChecklistItemCount ticked — unticked items are recorded as not done'),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: C.red))),
          const SizedBox(height: 12),
          Btn(busy ? 'Submitting…' : 'Submit checklist', _submit, busy: busy),
        ]);
      },
    );
  }
}

void ckViewRecord(BuildContext context, String id) {
  showSheet(context, 'Checklist', (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: Api.I.get('/api/checklists/$id'),
        builder: (ctx, snap) {
          if (snap.hasError) return InfoCard.red(Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
          final r = Map<String, dynamic>.from(snap.data!['checklist'] as Map);
          final answers = ((r['answers'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final sections = <String, List<Rec>>{};
          for (final a in answers) {
            sections.putIfAbsent(a['section'] as String, () => []).add(a);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_ckStyle[r['type']]?.$3 ?? r['type']} · ${fmtD(r['shiftDate'] as String?)}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${r['userName']}'),
                Muted('${locName(r['loc'] as String?)} · sent at ${fmtIstTime((r['submittedAt'] as num).toInt())} IST'),
                const SizedBox(height: 6),
                Pill('${r['ticked']}/${r['total']} ticked', r['ticked'] == r['total'] ? PillTone.grn : PillTone.org),
              ]),
            ),
            for (final s in sections.entries) ...[
              SecTitle(s.key),
              RowsCard([
                for (final a in s.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['done'] == true ? '✅' : '⬜'),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('${a['question']}',
                              style: TextStyle(color: a['done'] == true ? C.ink : C.mut))),
                    ]),
                  ),
              ]),
            ],
          ]);
        },
      ));
}

/// Home dashboard tiles: "sent / restaurants" per checklist today.
class ChecklistTiles extends StatefulWidget {
  const ChecklistTiles({super.key});
  @override
  State<ChecklistTiles> createState() => _ChecklistTilesState();
}

class _ChecklistTilesState extends State<ChecklistTiles> {
  @override
  void initState() {
    super.initState();
    Ck.I.load();
    Ck.I.startTicker();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Ck.I,
        builder: (context, _) {
          final locs = scopeLocs(S.loc).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SecTitle('Checklists · sent / ${locs == 1 ? 'restaurant' : 'restaurants'}'),
            StatGrid([
              for (final type in ['LUNCH', 'DINNER', 'CLOSING'])
                Builder(builder: (_) {
                  final w = Ck.I.windows.where((x) => x['type'] == type).firstOrNull;
                  final st = _ckStyle[type]!;
                  if (w == null) return Stat('…', '${st.$1} ${st.$3}');
                  final sent = Ck.I.subs(w).where((m) => S.loc == 'ALL' || m['loc'] == S.loc).length;
                  final ends = (w['endsAt'] as num?)?.toInt() ?? 0;
                  final closed = w['open'] != true && Ck.I.now >= ends;
                  final color = sent >= locs
                      ? C.grn
                      : (w['open'] == true ? C.org : (closed ? C.red : C.mut));
                  return Stat('$sent/$locs', '${st.$1} ${st.$3}', color: color, onTap: () => navState.go('chk'));
                }),
            ]),
          ]);
        },
      );
}
