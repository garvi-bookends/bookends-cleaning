import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'cleaning.dart';
import 'home.dart';
import 'shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _StaffRow {
  final String id;
  String? loc;
  int total = 0, ok = 0;
  _StaffRow(this.id);
  int get pct => (ok / (total == 0 ? 1 : total) * 100).round();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'week';
  List<Rec>? ckRecs;
  String? ckErr;

  List<String> get weeks => period == 'week' ? [weekId(today())] : recentWeeks(4);

  (String, String) get ckRange {
    final t = istYmd();
    final d = parseD(t);
    return period == 'week' ? (ymd(mondayOf(d)), t) : (ymd(addDays(d, -27)), t);
  }

  @override
  void initState() {
    super.initState();
    _loadCk();
  }

  Future<void> _loadCk() async {
    final (f, t) = ckRange;
    setState(() {
      ckRecs = null;
      ckErr = null;
    });
    try {
      final r = await Api.I.get('/api/checklists', query: {'from': f, 'to': t});
      if (mounted) setState(() => ckRecs = ((r['checklists'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => ckErr = e.message);
    }
  }

  List<Rec> _uniqueTasks(String loc) {
    final m = <String, Rec>{};
    for (final w in weeks) {
      for (final t in tasksFor(loc, w)) {
        m[t['id'] as String] = t;
      }
    }
    return m.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final locs = visibleLocations();
    final ms = {for (final l in locs) l: multiScore(l, weeks)};
    final avg = ms.isEmpty ? 0 : (ms.values.map((s) => s.overall).reduce((a, b) => a + b) / ms.length).round();

    // Violations
    var vClean = 0, vExp = 0, vLab = 0;
    final staff = <String, _StaffRow>{};
    final photos = <Rec>[];
    for (final l in locs) {
      for (final t in _uniqueTasks(l)) {
        if (t['status'] == 'rejected' || jobOverdue(t) || missingPhoto(t)) vClean++;
        final who = (t['completedBy'] ?? t['assigned']) as String?;
        if (who != null) {
          final r = staff.putIfAbsent(who, () => _StaffRow(who)..loc = l);
          r.total++;
          if (t['status'] == 'completed' && t['approved'] == true) r.ok++;
        }
        if (t['before'] != null || t['after'] != null) photos.add(t);
      }
      for (final p in productsFor(l).where(isActive)) {
        final k = expiryState(p['expiry'] as String?).k;
        if (k == 'expired' || k == 'soon') vExp++;
        if (p['labelled'] != true) vLab++;
      }
    }
    final staffRows = staff.values.toList()..sort((a, b) => b.pct - a.pct);

    return Column(children: [
      PageHeader('CLEANING REPORTS',
          sub: '${period == 'week' ? 'Weekly' : 'Monthly (4 weeks)'} · ${locs.length} location${locs.length == 1 ? '' : 's'}', showLoc: false),
      Expanded(
        child: PageBody(children: [
          ChipRow(const [('week', 'This week'), ('month', 'Last 4 weeks')], period, (k) {
            setState(() => period = k);
            _loadCk();
          }),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Ring(avg, size: 108, stroke: 12),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Muted('GROUP OVERALL SCORE', size: 11),
                  Text(scoreBand(avg), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scoreColor(avg))),
                  Muted(weeks.length == 1 ? weekLabel(weeks.first) : '${weekLabel(weeks.last)} → ${weekLabel(weeks.first)}', size: 12),
                ]),
              ),
            ]),
          ),
          const SecTitle('Location-wise compliance'),
          AppCard(
            child: Table(
              columnWidths: const {0: FlexColumnWidth(2.4)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(children: [
                  Muted('LOCATION', size: 11),
                  Muted('CLEAN', size: 11),
                  Muted('LABEL', size: 11),
                  Muted('EXPIRY', size: 11),
                  Muted('SCORE', size: 11),
                ]),
                for (final l in locs)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(locById(l)!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Muted(locById(l)!.city, size: 11),
                      ]),
                    ),
                    Text('${ms[l]!.clean}%'),
                    Text('${ms[l]!.label}%'),
                    Text('${ms[l]!.exp}%'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: scoreColor(ms[l]!.overall).withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                        child: Text('${ms[l]!.overall}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: scoreColor(ms[l]!.overall))),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
          if (S.perm.all) ...[const SecTitle('Surat vs Ahmedabad'), CityCompare(weeks: weeks)],
          const SecTitle('Violations'),
          StatGrid([
            Stat('$vClean', 'Cleaning', color: C.red),
            Stat('$vExp', 'Expiry', color: C.org),
            Stat('$vLab', 'Labelling', color: C.yel),
          ]),
          const SecTitle('Staff compliance'),
          if (staffRows.isEmpty)
            const EmptyState('👥', 'No work recorded yet')
          else
            RowsCard([
              for (final r in staffRows.take(14))
                LRow(
                  title: uname(r.id),
                  sub: '${locById(r.loc)?.code ?? '—'} · ${r.total} tasks · ${r.ok} approved',
                  trailing: Text('${r.pct}%', style: TextStyle(fontWeight: FontWeight.w800, color: scoreColor(r.pct))),
                ),
            ]),
          SecTitle('Photo evidence (${photos.length})'),
          if (photos.isEmpty)
            const EmptyState('📷', 'No photos yet')
          else
            GridView.count(
              crossAxisCount: (MediaQuery.of(context).size.width / 90).floor().clamp(3, 8),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final t in photos.take(24))
                  GestureDetector(
                    onTap: () => taskSheet(context, t['id'] as String),
                    child: Photo((t['after'] ?? t['before']) as String?, radius: 9),
                  ),
              ],
            ),
          ..._ckTable(locs),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Btn('🖨 Print / PDF', () => _pdf(locs, ms, avg, vClean, vExp, vLab, staffRows))),
            const SizedBox(width: 10),
            Expanded(child: Btn('⤓ Export CSV', () => _csv(locs), kind: BtnKind.sec)),
          ]),
        ]),
      ),
    ]);
  }

  Map<String, Map<String, (int, int)>> _ckCounts(List<String> locs) {
    final (f, t) = ckRange;
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <String, Map<String, (int, int)>>{};
    for (final l in locs) {
      final m = <String, (int, int)>{};
      for (final type in ['LUNCH', 'DINNER', 'CLOSING']) {
        var done = 0, due = 0;
        for (var d = parseD(f); !d.isAfter(parseD(t)); d = addDays(d, 1)) {
          final dy = ymd(d);
          final has = (ckRecs ?? []).any((r) => r['loc'] == l && r['type'] == type && r['shiftDate'] == dy);
          final w = {'LUNCH': 13 * 60 + 30, 'DINNER': 18 * 60, 'CLOSING': 25 * 60}[type]!;
          final end = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch + (w - 330) * 60000;
          if (has) {
            done++;
            due++;
          } else if (now >= end) {
            due++;
          }
        }
        m[type] = (done, due);
      }
      out[l] = m;
    }
    return out;
  }

  List<Widget> _ckTable(List<String> locs) {
    final (f, t) = ckRange;
    if (ckErr != null) return [const SecTitle('Daily checklists'), InfoCard.red(Text(ckErr!))];
    if (ckRecs == null) return [const SecTitle('Daily checklists'), const Muted('Loading checklist data…')];
    final c = _ckCounts(locs);
    return [
      SecTitle('Daily checklists · ${fmtD(f)} – ${fmtD(t)}'),
      AppCard(
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2.2)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            const TableRow(children: [
              Muted('LOCATION', size: 11),
              Muted('LUNCH', size: 11),
              Muted('DINNER', size: 11),
              Muted('CLOSING', size: 11),
              Muted('MISSED', size: 11),
            ]),
            for (final l in locs)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(locById(l)!.name, style: const TextStyle(fontSize: 13))),
                for (final type in ['LUNCH', 'DINNER', 'CLOSING'])
                  Builder(builder: (_) {
                    final (d, due) = c[l]![type]!;
                    final pct = due == 0 ? 100 : (d / due * 100).round();
                    return Text('$d/$due', style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor(pct)));
                  }),
                Builder(builder: (_) {
                  final missed = c[l]!.values.fold(0, (n, x) => n + x.$2 - x.$1);
                  return Align(
                      alignment: Alignment.centerLeft,
                      child: missed > 0 ? Pill('$missed', PillTone.red) : const Pill('NONE', PillTone.grn));
                }),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Btn('⤓ Export checklist CSV', _ckCsv, kind: BtnKind.sec, small: true),
    ];
  }

  String _q(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';

  Future<void> _share(String name, String body) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(body);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: name));
    toast('CSV exported');
  }

  Future<void> _csv(List<String> locs) async {
    final rows = <List<Object?>>[
      ['Location', 'City', 'Week', 'Month', 'Cleaning %', 'Weekly jobs %', 'Monthly jobs %', 'Labelling %', 'Expiry %', 'Overall',
        'Expired', 'Expiring7d', 'Pending', 'Rejected', 'MissingPhotos'],
    ];
    for (final l in locs) {
      final L = locById(l)!;
      final e = expiryStats(l);
      for (final w in weeks) {
        final c = cleaningStats(l, w);
        rows.add([
          L.name, L.city, w, monthOfWeek(w), c.pct, cleaningStats(l, w, freq: 'W').pct, cleaningStats(l, w, freq: 'M').pct,
          e.labelPct, e.score, (.4 * c.pct + .35 * e.score + .25 * e.labelPct).round(), e.expired, e.soon, c.pending, c.rejected, c.noPhoto,
        ]);
      }
    }
    await _share('bookends-cleaning-${ymd(today())}.csv', rows.map((r) => r.map(_q).join(',')).join('\n'));
  }

  Future<void> _ckCsv() async {
    final rows = <List<Object?>>[
      ['User', 'Checklist', 'Location', 'Date', 'Submitted (IST)', 'Ticked', 'Status'],
      for (final r in ckRecs ?? [])
        [r['userName'], r['type'], locName(r['loc'] as String?), r['shiftDate'], fmtIstTime((r['submittedAt'] as num).toInt()),
          '${r['ticked']}/${r['total']}', r['status']],
    ];
    await _share('bookends-checklists-${istYmd()}.csv', rows.map((r) => r.map(_q).join(',')).join('\n'));
  }

  Future<void> _pdf(List<String> locs, Map<String, Score> ms, int avg, int vc, int ve, int vl, List<_StaffRow> staff) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (c) => [
        pw.Text('Bookends Cleaning', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(
            '${period == 'week' ? 'Weekly report' : 'Monthly report'} · generated ${fmtDT(DateTime.now().millisecondsSinceEpoch)} · ${S.me?['name']}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        pw.Text('Group overall score: $avg% (${scoreBand(avg)})', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(weeks.length == 1 ? weekLabel(weeks.first) : '${weekLabel(weeks.last)} → ${weekLabel(weeks.first)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Location', 'City', 'Clean', 'Label', 'Expiry', 'Score'],
          data: [
            for (final l in locs)
              [locById(l)!.name, locById(l)!.city, '${ms[l]!.clean}%', '${ms[l]!.label}%', '${ms[l]!.exp}%', '${ms[l]!.overall}'],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E2A78)),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 12),
        pw.Text('Violations: cleaning $vc · expiry $ve · labelling $vl', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Text('Staff compliance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Staff', 'Location', 'Tasks', 'Approved', 'Rate'],
          data: [for (final r in staff.take(14)) [uname(r.id), locById(r.loc)?.code ?? '—', '${r.total}', '${r.ok}', '${r.pct}%']],
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'bookends-report-${ymd(today())}');
  }
}
