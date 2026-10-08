import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'checklists.dart';
import 'cleaning.dart';
import 'expiry.dart';
import 'manage.dart';
import 'profile.dart';
import 'shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    return S.me?['role'] == 'staff' ? const _StaffHome() : const _Dashboard();
  }
}

// ---------------------------------------------------------------------------
// Kitchen Staff: big buttons
// ---------------------------------------------------------------------------
class _StaffHome extends StatelessWidget {
  const _StaffHome();
  @override
  Widget build(BuildContext context) {
    final nav = context.read<Nav>();
    final loc = (S.me?['loc'] as String?) ?? S.loc;
    final wk = weekId(today());
    final todo = visibleLocations().expand((l) => tasksFor(l, wk)).where((t) => t['status'] == 'pending' || t['status'] == 'rejected').toList()
      ..sort((a, b) {
        final m = (isMine(b) ? 1 : 0) - (isMine(a) ? 1 : 0);
        return m != 0 ? m : '${a['due']}'.compareTo('${b['due']}');
      });
    final ex = expiryStats(loc);
    final unlabelled = productsFor(loc).where((p) => isActive(p) && p['labelled'] != true).length;
    final expired = productsFor(loc).where((p) => isActive(p) && expiryState(p['expiry'] as String?).k == 'expired').toList();
    final first = ((S.me?['name'] ?? '') as String).split(' ').first;

    return Column(children: [
      PageHeader('Hi $first', sub: locName(loc), showLoc: false),
      Expanded(
        child: PageBody(children: [
          const SizedBox(height: 4),
          if (tabAllowed('clean'))
            _Big('🧽', const Color(0xFFE8F0FB), 'CLEANING',
                todo.isEmpty ? 'All jobs done ✓' : '${todo.length} job${todo.length == 1 ? '' : 's'} to do',
                todo.isEmpty ? null : todo.length, () => nav.go('clean')),
          if (tabAllowed('lab'))
            _Big('🏷️', const Color(0xFFFFF7E2), 'LABEL A PRODUCT', 'Name it, set the dates, add a photo',
                unlabelled == 0 ? null : unlabelled, () => productForm(context, null, noun: 'label')),
          _Big('📅', const Color(0xFFFDE9E4), 'CHECK EXPIRY',
              ex.expired + ex.soon == 0 ? 'Nothing expiring' : '${ex.expired} expired · ${ex.soon} expiring soon',
              ex.expired + ex.soon == 0 ? null : ex.expired + ex.soon, () => nav.go('exp')),
          if (tabAllowed('chk'))
            _Big('📋', const Color(0xFFEEF2FF), 'DAILY CHECKLIST', 'Lunch · Dinner · Closing', null, () => nav.go('chk')),
          if (todo.isNotEmpty) ...[
            const SecTitle('Jobs still to do this week'),
            RowsCard([for (final t in todo.take(8)) TaskRow(t)]),
          ],
          if (expired.isNotEmpty) ...[
            const SecTitle('Throw these away 🔴'),
            RowsCard([for (final p in expired.take(6)) ProductRow(p)]),
          ],
          const SizedBox(height: 14),
          const InfoCard.blue(Text.rich(TextSpan(children: [
            TextSpan(text: 'Every job needs a '),
            TextSpan(text: 'photo', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: '.\nEvery product needs a '),
            TextSpan(text: 'label', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: '.'),
          ]))),
        ]),
      ),
    ]);
  }
}

class _Big extends StatelessWidget {
  final String emoji, title, sub;
  final Color bg;
  final int? count;
  final VoidCallback onTap;
  const _Big(this.emoji, this.bg, this.title, this.sub, this.count, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Row(children: [
              Tile(emoji, bg, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  Text(sub, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.mut)),
                ]),
              ),
              count != null
                  ? Text('$count', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.brand))
                  : const Text('›', style: TextStyle(fontSize: 32, color: Color(0xFFC8CEE2))),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Everyone else: dashboard
// ---------------------------------------------------------------------------
class _Dashboard extends StatelessWidget {
  const _Dashboard();
  @override
  Widget build(BuildContext context) {
    final nav = context.read<Nav>();
    final p = S.perm;
    final loc = S.loc;
    final wk = weekId(today());
    final locs = scopeLocs(loc);
    final scores = {for (final l in locs) l: scoreFor(l, wk)};
    int avg(int Function(Score) f) => scores.isEmpty ? 0 : (scores.values.map(f).reduce((a, b) => a + b) / scores.length).round();
    final overall = avg((s) => s.overall);
    final cs = cleaningStats(loc, wk);
    final es = expiryStats(loc);
    final urgent = buildAlerts().where((a) => a.sev >= 2).length;
    final awaiting = tasksAwaitingApproval().length;

    return Column(children: [
      PageHeader('BOOKENDS CLEANING', sub: '${p.label} · ${loc == 'ALL' ? 'All locations' : locName(loc)}'),
      Expanded(
        child: PageBody(onRefresh: () async {
          await S.sync();
          if (p.superadmin) await refreshAdminQueue();
        }, children: [
          if (p.superadmin) const AdminQueueCards(),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: C.headerGradient, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('OVERALL COMPLIANCE · ${weekLabel(wk)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                  const SizedBox(height: 8),
                  Text(scoreBand(overall), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      '${loc == 'ALL' ? '${locs.length} locations' : locName(loc)} · updated ${fmtDT((S.lastSync ?? DateTime.now()).millisecondsSinceEpoch)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 12.5)),
                ]),
              ),
              Ring(overall, size: 112, stroke: 12, light: true),
            ]),
          ),
          const SizedBox(height: 10),
          StatGrid([
            Stat('${avg((s) => s.clean)}%', 'Cleaning %', color: scoreColor(avg((s) => s.clean))),
            Stat('${avg((s) => s.label)}%', 'Labelling %', color: scoreColor(avg((s) => s.label))),
            Stat('${avg((s) => s.exp)}%', 'Expiry ctrl %', color: scoreColor(avg((s) => s.exp))),
          ]),
          const SizedBox(height: 8),
          StatGrid([
            Stat('${es.expired}', 'Expired', color: es.expired > 0 ? C.red : C.mut, onTap: () => nav.go('exp', exp: 'expired')),
            Stat('${es.soon}', 'Expiring 7d', color: es.soon > 0 ? C.org : C.mut, onTap: () => nav.go('exp', exp: 'soon')),
            Stat('${cs.pending}', 'Pending tasks', onTap: () => _goClean(nav, 'pending')),
            Stat('${cs.rejected}', 'Rejected', color: cs.rejected > 0 ? C.red : C.mut, onTap: () => _goClean(nav, 'rejected')),
            Stat('${cs.noPhoto}', 'Missing photos', color: cs.noPhoto > 0 ? C.org : C.mut, onTap: () => _goClean(nav, 'nophoto')),
            Stat('$urgent', 'Urgent alerts', color: urgent > 0 ? C.red : C.mut, onTap: () => alertsSheet(context)),
          ]),
          if (tabAllowed('chk')) const ChecklistTiles(),
          const SecTitle('Quick actions'),
          Row(children: [
            Expanded(
              child: Btn('✓ Do a clean', !p.readonly && tabAllowed('clean') ? () => _goClean(nav, 'all') : null),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: p.approve
                  ? Btn('☑ Approvals ($awaiting)', () => nav.go('manage', manageTo: 'review'), kind: BtnKind.sec)
                  : Btn('🏷 Labels', () => nav.go('lab'), kind: BtnKind.sec),
            ),
          ]),
          if (p.all) ...[
            const SecTitle('Locations · this week'),
            RowsCard([
              for (final l in kLocations)
                _LeagueRow(l, scores[l.id] ?? scoreFor(l.id, wk), () => locDash(context, l.id)),
            ]),
            const SecTitle('Surat vs Ahmedabad'),
            CityCompare(weeks: [wk]),
          ] else ...[
            const SecTitle('Needs action this week'),
            Builder(builder: (_) {
              final need = locs.expand((l) => tasksFor(l, wk)).where((t) => t['status'] != 'completed' || t['approved'] != true).take(5).toList();
              if (need.isEmpty) return const EmptyState('🎉', 'All caught up for this week');
              return RowsCard([for (final t in need) TaskRow(t)]);
            }),
          ],
        ]),
      ),
    ]);
  }

  void _goClean(Nav nav, String f) {
    if (S.loc == 'ALL') {
      final v = visibleLocations();
      if (v.isNotEmpty) S.loc = v.first;
    }
    nav.go('clean', clean: f);
  }
}

class _LeagueRow extends StatelessWidget {
  final Location l;
  final Score s;
  final VoidCallback onTap;
  const _LeagueRow(this.l, this.s, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scoreColor(s.overall), borderRadius: BorderRadius.circular(12)),
              child: Text('${s.overall}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${l.city} · clean ${s.clean}% · label ${s.label}% · ${s.e.expired} expired',
                    style: const TextStyle(fontSize: 12.5, color: C.mut)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                      value: s.overall / 100, minHeight: 5, color: scoreColor(s.overall), backgroundColor: const Color(0xFFE6E9F4)),
                ),
              ]),
            ),
            const Text(' ›', style: TextStyle(fontSize: 26, color: C.chev)),
          ]),
        ),
      );
}

/// Surat vs Ahmedabad comparison table.
class CityCompare extends StatelessWidget {
  final List<String> weeks;
  const CityCompare({super.key, required this.weeks});

  Map<String, num> _city(String city) {
    final ls = kLocations.where((l) => l.city == city).map((l) => l.id).toList();
    final ms = ls.map((l) => multiScore(l, weeks)).toList();
    final newest = ls.map((l) => scoreFor(l, weeks.first)).toList();
    double avg(int Function(Score) f) => ms.isEmpty ? 0 : ms.map(f).reduce((a, b) => a + b) / ms.length;
    int sum(int Function(Score) f) => newest.isEmpty ? 0 : newest.map(f).reduce((a, b) => a + b);
    return {
      'overall': avg((s) => s.overall).round(),
      'clean': avg((s) => s.clean).round(),
      'label': avg((s) => s.label).round(),
      'exp': avg((s) => s.exp).round(),
      'expired': sum((s) => s.e.expired),
      'soon': sum((s) => s.e.soon),
      'pending': sum((s) => s.c.pending),
      'rejected': sum((s) => s.c.rejected),
    };
  }

  @override
  Widget build(BuildContext context) {
    final a = _city('Surat'), b = _city('Ahmedabad');
    const rows = [
      ('overall', 'Overall score', true),
      ('clean', 'Deep cleaning', true),
      ('label', 'Labelling', true),
      ('exp', 'Expiry control', true),
      ('expired', 'Expired items', false),
      ('soon', 'Expiring ≤7d', false),
      ('pending', 'Pending tasks', false),
      ('rejected', 'Rejected tasks', false),
    ];
    TextStyle st(bool win) => TextStyle(fontWeight: FontWeight.w800, color: win ? C.grn : C.ink);
    return AppCard(
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2)},
        children: [
          const TableRow(children: [
            Padding(padding: EdgeInsets.only(bottom: 8), child: Muted('METRIC', size: 11)),
            Muted('SURAT', size: 11),
            Muted('AHMEDABAD', size: 11),
          ]),
          for (final (k, label, pct) in rows)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(label)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${a[k]}${pct ? '%' : ''}', style: st(pct ? a[k]! > b[k]! : a[k]! < b[k]!)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${b[k]}${pct ? '%' : ''}', style: st(pct ? b[k]! > a[k]! : b[k]! < a[k]!)),
              ),
            ]),
        ],
      ),
    );
  }
}

/// One kitchen's dashboard (opened from the league table).
void locDash(BuildContext context, String locId) {
  final nav = context.read<Nav>();
  final l = locById(locId)!;
  final wk = weekId(today());
  final s = scoreFor(locId, wk);
  final alerts = buildAlerts().where((a) => a.loc == locId).toList();
  showSheet(context, l.name, (ctx) {
    void go(String tab) {
      Navigator.pop(ctx);
      S.loc = locId;
      S.save();
      nav.go(tab);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: C.headerGradient, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l.city.toUpperCase()} · ${weekLabel(wk)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(l.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              Text('Overall compliance score · ${scoreBand(s.overall)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12.5)),
            ]),
          ),
          Ring(s.overall, size: 100, stroke: 11, light: true),
        ]),
      ),
      const SizedBox(height: 10),
      AppCard(
        child: Column(children: [
          Bar('Deep-cleaning compliance', s.clean),
          Bar('Labelling compliance', s.label),
          Bar('Expiry control', s.exp),
        ]),
      ),
      const SizedBox(height: 10),
      StatGrid([
        Stat('${s.e.expired}', 'Expired', color: s.e.expired > 0 ? C.red : C.mut),
        Stat('${s.e.soon}', 'Expiring 7d', color: s.e.soon > 0 ? C.org : C.mut),
        Stat('${s.e.month}', 'Expiring 30d', color: s.e.month > 0 ? C.yel : C.mut),
        Stat('${s.c.pending}', 'Pending'),
        Stat('${s.c.rejected}', 'Rejected', color: s.c.rejected > 0 ? C.red : C.mut),
        Stat('${s.c.noPhoto}', 'No photos', color: s.c.noPhoto > 0 ? C.org : C.mut),
      ]),
      SecTitle('Open alerts (${alerts.length})'),
      if (alerts.isEmpty) const EmptyState('✅', 'No open alerts') else RowsCard([for (final a in alerts.take(8)) AlertRow(a)]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Btn('Cleaning', () => go('clean'), small: true)),
        const SizedBox(width: 8),
        Expanded(child: Btn('Expiry', () => go('exp'), small: true, kind: BtnKind.sec)),
        const SizedBox(width: 8),
        Expanded(child: Btn('Labels', () => go('lab'), small: true, kind: BtnKind.sec)),
      ]),
    ]);
  });
}
