import 'dart:math';

import '../core/dates.dart';
import 'constants.dart';
import 'store.dart';

/// Ports of the website's job, scoring and alert functions.
Store get S => Store.I;

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------
Rec? userById(String? id) {
  if (id == null) return null;
  for (final u in S.users) {
    if (u['id'] == id) return u;
  }
  if (S.me?['id'] == id) return S.me;
  return null;
}

String uname(String? id) => (userById(id)?['name'] as String?) ?? '—';

String initials(String? name) {
  final w = (name ?? '').trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  if (w.length == 1) return w[0].substring(0, min(2, w[0].length)).toUpperCase();
  return (w.first[0] + w.last[0]).toUpperCase();
}

// ---------------------------------------------------------------------------
// Jobs (built-in template + Super Admin overrides from /api/checklist/items)
// ---------------------------------------------------------------------------
class Job {
  final String tk, name, zone, freq, jobType;
  final int? day;
  final List<String>? locs; // null = every kitchen
  final List<String> assignees;
  final String? atTime, endDate;
  final bool custom;
  Job(this.tk, this.name, this.zone, this.freq, this.day, this.locs, this.assignees, this.atTime, this.endDate,
      this.jobType, this.custom);
  bool covers(String loc) => locs == null || locs!.contains(loc);
}

List<String> assigneesOf(Map o) {
  final a = o['assignees'];
  if (a is List && a.isNotEmpty) return a.map((e) => '$e').toSet().toList();
  final one = o['assignedTo'] ?? o['assigned'];
  return one == null ? [] : ['$one'];
}

List<String>? _normLocs(Map o) {
  final l = o['locs'];
  if (l is List && l.isNotEmpty) {
    final ok = l.map((e) => '$e').where((id) => locById(id) != null).toList();
    if (ok.isNotEmpty) return ok;
  }
  if (o['loc'] != null && locById('${o['loc']}') != null) return ['${o['loc']}'];
  return null;
}

Job? jobFor(String tk) {
  final o = S.checklist[tk] ?? const <String, dynamic>{};
  final b = builtinByTk(tk);
  if (b == null && o['custom'] != true) return null;
  final freq = (o['freq'] ?? b?.t.freq ?? 'W') as String;
  final day = o['freq'] != null ? (o['day'] as num?)?.toInt() : ((o['day'] as num?)?.toInt() ?? b?.t.day);
  return Job(
    tk,
    (o['name'] ?? b?.t.area ?? tk) as String,
    (o['zone'] ?? b?.t.zone ?? 'Other') as String,
    freq,
    day,
    _normLocs(o),
    assigneesOf(o),
    o['atTime'] as String?,
    o['endDate'] as String?,
    (o['jobType'] ?? 'cleaning') as String,
    o['custom'] == true,
  );
}

bool serviceLive(String tk) {
  final o = S.checklist[tk];
  return o != null && o['enabled'] == true && o['deleted'] != true;
}

String tkeyOf(Rec t) => (t['tk'] ?? (t['id'] as String).split('-').last) as String;

List<Job> checklistJobs(String freq, String loc) {
  final out = <Job>[];
  final builtins = freq == 'W' ? kBuiltinWeekly : (freq == 'M' ? kBuiltinMonthly : const <BuiltinJob>[]);
  for (final b in builtins) {
    if (!serviceLive(b.tk)) continue;
    final j = jobFor(b.tk)!;
    if (j.covers(loc)) out.add(j);
  }
  for (final o in S.checklist.values) {
    if (o['custom'] == true && serviceLive(o['tkey'] as String) && o['freq'] == freq) {
      final j = jobFor(o['tkey'] as String);
      if (j != null && j.covers(loc)) out.add(j);
    }
  }
  return out;
}

int slotOf(String tk) => int.tryParse(tk.substring(1)) ?? 0;

bool taskLive(Rec t) {
  final tk = tkeyOf(t);
  if (!serviceLive(tk)) return false;
  final j = jobFor(tk);
  if (j == null) return false;
  if (j.covers(t['loc'] as String)) return true;
  return t['status'] != 'pending' ||
      t['before'] != null ||
      t['after'] != null ||
      t['completedAt'] != null ||
      t['completedBy'] != null ||
      t['approved'] != null;
}

Rec _newTask(Location l, String period, Job tp, String due, String suffix) {
  final people = tp.assignees;
  String? def;
  if (people.isEmpty) {
    for (final u in S.users) {
      if (u['loc'] == l.id && u['role'] == 'manager') {
        def = u['id'] as String;
        break;
      }
    }
    if (def == null) {
      for (final u in S.users) {
        if (u['loc'] == l.id) {
          def = u['id'] as String;
          break;
        }
      }
    }
  }
  final r = <String, dynamic>{
    'id': 'T-${l.code}-$period-${tp.tk}$suffix',
    'loc': l.id,
    'period': period,
    'freq': tp.freq,
    'area': tp.name,
    'zone': tp.zone,
    'tk': tp.tk,
    'assigned': people.isNotEmpty ? people.first : def,
    'due': due,
    'status': 'pending',
    'before': null,
    'after': null,
    'approved': null,
    'approvedBy': null,
    'approvedAt': null,
    'reject': '',
    'completedAt': null,
    'completedBy': null,
    'note': '',
    '_u': 0,
  };
  if (people.isNotEmpty) r['assignees'] = people;
  if (tp.atTime != null) r['time'] = tp.atTime;
  if (tp.jobType != 'cleaning') r['jobType'] = tp.jobType;
  return r;
}

/// Create this week's and month's jobs for every kitchen (ensureJobs).
void ensureJobs() {
  if (S.me == null || S.perm.readonly) return;
  final t = today();
  final mon = mondayOf(t);
  final wid = weekId(mon);
  final mid = monthId(t);
  var added = false;
  void add(Rec r, Job tp) {
    if (tp.endDate != null && (r['due'] as String).compareTo(tp.endDate!) > 0) return;
    if (S.tasks.containsKey(r['id'])) return;
    S.queue('tasks', r);
    added = true;
  }

  for (final l in kLocations) {
    for (final tp in checklistJobs('W', l.id)) {
      final off = tp.day ?? 1 + (slotOf(tp.tk) % 6);
      add(_newTask(l, wid, tp, ymd(addDays(mon, off)), ''), tp);
    }
    for (final tp in checklistJobs('M', l.id)) {
      final due = ymd(DateTime(t.year, t.month, min(28, 6 + slotOf(tp.tk) * 2)));
      add(_newTask(l, mid, tp, due, ''), tp);
    }
    for (final tp in checklistJobs('D', l.id)) {
      for (var dd = 0; dd < 7; dd++) {
        add(_newTask(l, wid, tp, ymd(addDays(mon, dd)), '-d$dd'), tp);
      }
    }
  }
  if (added) {
    S.save();
    S.schedulePush();
  }
}

String cleanName(Rec t) {
  final j = jobFor(tkeyOf(t));
  return (j?.name ?? t['area'] ?? 'Job') as String;
}

int? fixedDay(Rec t) => jobFor(tkeyOf(t))?.day;
bool isTuesdayJob(Rec t) => t['freq'] == 'W' && fixedDay(t) == 1;

// ---------------------------------------------------------------------------
// Scope
// ---------------------------------------------------------------------------
bool isMine(Rec t) {
  final id = S.myId;
  final a = t['assignees'];
  return t['assigned'] == id || (a is List && a.contains(id));
}

List<String> visibleLocations() {
  if (S.perm.all) return kLocations.map((l) => l.id).toList();
  final own = S.me?['loc'] as String?;
  final out = <String>[if (own != null) own];
  for (final t in S.tasks.values) {
    final l = t['loc'] as String?;
    if (l != null && !out.contains(l) && isMine(t) && taskLive(t)) out.add(l);
  }
  return out;
}

List<String> scopeLocs(String loc) => loc == 'ALL' ? visibleLocations() : [loc];

bool isGuestLoc(String loc) => !S.perm.all && loc != S.me?['loc'];

Iterable<Rec> _tasksAt(String loc, {String? freq, bool cleaningOnly = true}) {
  final guest = isGuestLoc(loc);
  return S.tasks.values.where((t) {
    if (t['loc'] != loc) return false;
    if (cleaningOnly && (t['jobType'] ?? 'cleaning') != 'cleaning') return false;
    if (!taskLive(t)) return false;
    if (guest && !isMine(t)) return false;
    if (freq != null && t['freq'] != freq) return false;
    return true;
  });
}

/// Tasks of one week (monthly ones belong to that week's month).
List<Rec> tasksFor(String loc, String wk, {String? freq}) {
  final mo = monthOfWeek(wk);
  return _tasksAt(loc, freq: freq).where((t) => t['freq'] == 'M' ? t['period'] == mo : t['period'] == wk).toList();
}

List<Rec> tasksInRange(String loc, String from, String to, {String? freq, bool cleaningOnly = true}) =>
    _tasksAt(loc, freq: freq, cleaningOnly: cleaningOnly).where((t) {
      final d = (t['due'] ?? '') as String;
      return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
    }).toList();

bool missingPhoto(Rec t) => t['status'] == 'completed' && t['before'] == null && t['after'] == null;
bool jobOverdue(Rec t) => t['status'] == 'pending' && daysBetween(ymd(today()), (t['due'] ?? '') as String) < 0;

bool canDoTask(Rec t) => !S.perm.readonly && (S.perm.all || S.me?['loc'] == t['loc'] || isMine(t));

// ---------------------------------------------------------------------------
// Products
// ---------------------------------------------------------------------------
bool isActive(Rec p) => p['status'] != 'Inactive';
String labelCode(Rec p) => (p['code'] ?? p['id']) as String;

List<Rec> productsFor(String loc) {
  final locs = scopeLocs(loc);
  final own = S.me?['role'] == 'staff';
  return S.products.values.where((p) => locs.contains(p['loc']) && (!own || p['by'] == S.myId)).toList();
}

class ExpState {
  final String k, label, emoji;
  final int days;
  const ExpState(this.k, this.label, this.emoji, this.days);
}

ExpState expiryState(String? exp) {
  final d = daysBetween(ymd(today()), exp ?? '');
  if (d < 0) return ExpState('expired', 'EXPIRED', '🔴', d);
  if (d <= 7) return ExpState('soon', '${d}d LEFT', '🟠', d);
  if (d <= 30) return ExpState('month', '${d}d LEFT', '🟡', d);
  return ExpState('safe', 'SAFE', '🔵', d);
}

/// 3-state version used by the Expiry table.
(String, String) expiryStatus(String? exp) {
  final d = daysBetween(ymd(today()), exp ?? '');
  if (d < 0) return ('expired', 'EXPIRED');
  if (d <= 7) return ('soon', 'EXPIRING SOON');
  return ('active', 'ACTIVE');
}

String newProductId(String loc) {
  final code = locById(loc)?.code ?? 'X';
  final r = Random.secure();
  String id;
  do {
    final rnd = List.generate(3, (_) => r.nextInt(36).toRadixString(36)).join();
    id = 'P-$code-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$rnd'.toUpperCase();
  } while (S.products.values.any((x) => labelCode(x).toUpperCase() == id));
  return id;
}

// ---------------------------------------------------------------------------
// Scores
// ---------------------------------------------------------------------------
class CleanStats {
  int total = 0, done = 0, approved = 0, rejected = 0, pending = 0, overdue = 0, noPhoto = 0;
  int get pct => (approved / (total == 0 ? 1 : total) * 100).round();
}

CleanStats statsOf(Iterable<Rec> ts) {
  final s = CleanStats();
  final now = ymd(today());
  for (final t in ts) {
    s.total++;
    if (t['status'] == 'completed') {
      s.done++;
      if (t['approved'] == true) s.approved++;
    } else if (t['status'] == 'rejected') {
      s.rejected++;
    } else {
      s.pending++;
      if (daysBetween(now, (t['due'] ?? '') as String) < 0) s.overdue++;
    }
    if (missingPhoto(t)) s.noPhoto++;
  }
  return s;
}

CleanStats cleaningStats(String loc, String wk, {String? freq}) =>
    statsOf(scopeLocs(loc).expand((l) => tasksFor(l, wk, freq: freq)));

class ExpStats {
  int total = 0, expired = 0, soon = 0, month = 0, safe = 0, labelled = 0;
  int get labelPct => total == 0 ? 100 : (labelled / total * 100).round();
  int get score => total == 0 ? 100 : max(0, ((total - expired - 0.5 * soon) / total * 100).round());
}

ExpStats expiryStats(String loc) {
  final s = ExpStats();
  for (final p in productsFor(loc).where(isActive)) {
    s.total++;
    switch (expiryState(p['expiry'] as String?).k) {
      case 'expired':
        s.expired++;
      case 'soon':
        s.soon++;
      case 'month':
        s.month++;
      default:
        s.safe++;
    }
    if (p['labelled'] == true) s.labelled++;
  }
  return s;
}

class Score {
  final int clean, exp, label, overall;
  final CleanStats c;
  final ExpStats e;
  Score(this.c, this.e, {int? cleanPct})
      : clean = cleanPct ?? c.pct,
        exp = e.score,
        label = e.labelPct,
        overall = (0.40 * (cleanPct ?? c.pct) + 0.35 * e.score + 0.25 * e.labelPct).round();
}

Score scoreFor(String loc, String wk) => Score(cleaningStats(loc, wk), expiryStats(loc));

Score multiScore(String loc, List<String> weeks) {
  final cs = weeks.map((w) => cleaningStats(loc, w).pct).toList();
  final avg = cs.isEmpty ? 0 : (cs.reduce((a, b) => a + b) / cs.length).round();
  return Score(cleaningStats(loc, weeks.first), expiryStats(loc), cleanPct: avg);
}

String scoreBand(int p) => p >= 90 ? 'Excellent' : (p >= 75 ? 'On track' : (p >= 60 ? 'Needs attention' : 'Critical'));

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------
class Alert {
  final String id, type, title, body, goKind, goId;
  final String? loc;
  final int sev;
  Alert(this.id, this.sev, this.type, this.loc, this.title, this.body, this.goKind, this.goId);
}

/// Checklist reminders are supplied by the checklist screen's poller.
List<Alert> checklistReminders = [];

List<Alert> buildAlerts() {
  final out = <Alert>[];
  final wk = weekId(today());
  final now = ymd(today());
  for (final l in visibleLocations()) {
    for (final t in tasksFor(l, wk)) {
      final id = t['id'] as String;
      final st = t['status'];
      if (st == 'pending' && daysBetween(now, (t['due'] ?? '') as String) < 0) {
        out.add(Alert('a1$id', 2, 'Cleaning overdue', l, cleanName(t),
            'Due ${fmtD(t['due'] as String?)} · ${uname(t['assigned'] as String?)}', 'task', id));
      }
      if (missingPhoto(t)) out.add(Alert('a2$id', 1, 'Photo missing', l, cleanName(t), 'Photo not uploaded', 'task', id));
      if (st == 'rejected') {
        final r = (t['reject'] ?? '') as String;
        out.add(Alert('a3$id', 2, 'Task rejected', l, cleanName(t), r.isEmpty ? 'Rejected by manager' : r, 'task', id));
      }
      if (st == 'completed' && t['approved'] != true && (t['before'] != null || t['after'] != null)) {
        out.add(Alert('a6$id', 0, 'Awaiting approval', l, cleanName(t),
            'Completed by ${uname(t['assigned'] as String?)}', 'task', id));
      }
    }
    for (final p in productsFor(l).where(isActive)) {
      final id = p['id'] as String;
      final e = expiryState(p['expiry'] as String?);
      final batch = (p['batch'] ?? '') as String;
      if (e.k == 'expired') {
        out.add(Alert('a4$id', 3, 'Product expired', l, '${p['name']}',
            'Expired ${fmtD(p['expiry'] as String?)} · batch $batch · discard', 'product', id));
      } else if (e.k == 'soon') {
        out.add(Alert('a5$id', 2, 'Expiring in ${e.days}d', l, '${p['name']}',
            'Use by ${fmtD(p['expiry'] as String?)} · ${p['storage'] ?? ''}', 'product', id));
      }
      if (p['labelled'] != true) {
        out.add(Alert('a7$id', 1, 'Label missing', l, '${p['name']}', 'No label printed · batch $batch', 'product', id));
      }
    }
  }
  final all = [...checklistReminders, ...out];
  // stable sort by severity, highest first
  final idx = {for (var i = 0; i < all.length; i++) all[i]: i};
  all.sort((a, b) => b.sev != a.sev ? b.sev - a.sev : idx[a]! - idx[b]!);
  return all;
}

List<Alert> unreadAlerts() => buildAlerts().where((a) => !S.read.containsKey(a.id)).toList();
