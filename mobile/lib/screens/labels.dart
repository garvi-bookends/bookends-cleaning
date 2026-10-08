import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'expiry.dart';
import 'shell.dart';

void markLabelled(BuildContext ctx, Rec p) {
  p
    ..['labelled'] = true
    ..['labelledAt'] = DateTime.now().millisecondsSinceEpoch;
  S.touch('products', p);
  S.logAct('label', 'Label applied: ${p['name']}', p['loc'] as String?);
  Navigator.pop(ctx);
  toast('Label recorded ✓');
}

class LabelsScreen extends StatelessWidget {
  const LabelsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final nav = context.watch<Nav>();
    final loc = S.loc;
    final ps = productsFor(loc);
    final e = expiryStats(loc);
    final missing = ps.where((p) => p['labelled'] != true).length;
    final f = nav.labFilter;
    final shown = ps.where((p) => f == 'missing' ? p['labelled'] != true : (f == 'done' ? p['labelled'] == true : true)).toList();

    return Column(children: [
      PageHeader('PRODUCT LABELLING', sub: locName(loc)),
      Expanded(
        child: PageBody(
          fab: S.perm.readonly ? null : Fab('＋ Add Labeling', () => productForm(context, null, noun: 'label')),
          children: [
            AppCard(
              child: Row(children: [
                Ring(e.labelPct),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Labelling compliance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${e.labelled} of ${ps.length} containers have a label written and applied'),
                    Muted('$missing container${missing == 1 ? '' : 's'} missing a label'),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            ChipRow([
              ('all', 'All ${ps.length}'),
              ('missing', 'Missing $missing'),
              ('done', 'Labelled ${ps.length - missing}'),
            ], f, (k) {
              nav.labFilter = k;
              nav.refresh();
            }),
            if (shown.isEmpty)
              const EmptyState('🏷', 'Nothing here')
            else
              RowsCard([
                for (final p in shown)
                  Builder(builder: (_) {
                    final st = expiryState(p['expiry'] as String?);
                    final ok = p['labelled'] == true;
                    return LRow(
                      leading: Tile(ok ? '🏷' : '⚠️', ok ? const Color(0xFFE8F0FB) : const Color(0xFFFDE8E9)),
                      title: '${p['name']}',
                      sub: '${loc == 'ALL' ? '${locById(p['loc'] as String?)?.name} · ' : ''}use by ${fmtD(p['expiry'] as String?)}',
                      pills: [
                        ok ? const Pill('LABEL OK', PillTone.grn) : const Pill('LABEL MISSING', PillTone.red),
                        Pill('${st.emoji} ${st.label}',
                            st.k == 'expired' ? PillTone.red : (st.k == 'soon' ? PillTone.org : (st.k == 'month' ? PillTone.yel : PillTone.grn))),
                        if (!isActive(p)) const Pill('INACTIVE', PillTone.gry),
                      ],
                      onTap: () => labelSheet(context, p['id'] as String),
                    );
                  }),
              ]),
          ],
        ),
      ),
    ]);
  }
}

void labelSheet(BuildContext context, String id) {
  final p0 = S.products[id];
  if (p0 == null) return;
  showSheet(context, '${p0['name']}', (ctx) {
    final p = S.products[id] ?? p0;
    final (k, label) = expiryStatus(p['expiry'] as String?);
    final initialsTxt = (p['initials'] ?? '') as String;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p['photo'] != null) ...[
        GestureDetector(
          onTap: () => showPhotoViewer(ctx, p['photo'] as String),
          child: Photo(p['photo'] as String, height: 190, width: double.infinity, radius: 16),
        ),
        const SizedBox(height: 10),
      ],
      const InfoCard(Text('Copy this onto a blank sticker and put it on the container.',
          style: TextStyle(fontWeight: FontWeight.w700))),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF111111), width: 3)),
        child: Column(children: [
          _wl('Product', '${p['name']}', big: true),
          _wl('MFG', fmtD(p['opened'] as String?)),
          _wl('Use by', fmtD(p['expiry'] as String?), pill: true),
          _wl('Initials', initialsTxt.isEmpty ? '—' : initialsTxt, last: true),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(children: [
          KV.text('Name', '${p['name']}', bold: true),
          if ((p['cat'] ?? '') != '') KV.text('Category', '${p['cat']}'),
          KV.text('MFG date', fmtD(p['opened'] as String?)),
          KV.text('Expiry date', '${fmtD(p['expiry'] as String?)} · ${relDays(p['expiry'] as String?)}'),
          KV('Status', Align(alignment: Alignment.centerLeft, child: Pill(label, k == 'expired' ? PillTone.red : (k == 'soon' ? PillTone.org : PillTone.grn)))),
          KV.text('Kitchen', locName(p['loc'] as String?)),
          KV.text('Added by', '${uname(p['by'] as String?)}${initialsTxt.isNotEmpty ? ' · $initialsTxt' : ''}'),
          KV.text('Label', p['labelled'] == true ? '✓ applied ${fmtDT((p['labelledAt'] as num?)?.toInt())}' : 'not written yet'),
          if ((p['batch'] ?? '') != '') KV.text('Batch', '${p['batch']} · ${p['qty'] ?? ''} ${p['unit'] ?? ''}'),
          if ((p['storage'] ?? '') != '') KV.text('Storage', '${p['storage']}'),
          if ((p['note'] ?? '') != '') KV.text('Notes', '${p['note']}'),
        ]),
      ),
      const SizedBox(height: 12),
      if (!S.perm.readonly && p['labelled'] != true) ...[
        Btn('✓ I have written it and stuck it on', () => markLabelled(ctx, p), kind: BtnKind.ok),
        const SizedBox(height: 10),
      ],
      Row(children: [
        if (!S.perm.readonly) ...[
          Expanded(child: Btn('Edit', () {
            Navigator.pop(ctx);
            productForm(context, id);
          }, kind: BtnKind.sec)),
          const SizedBox(width: 10),
        ],
        Expanded(child: Btn('Done', () => Navigator.pop(ctx))),
      ]),
    ]);
  });
}

Widget _wl(String k, String v, {bool big = false, bool pill = false, bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFC6CBDF), width: 2))),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(k.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.mut)),
        ),
        Expanded(
          child: pill
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                    child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                  ),
                )
              : Text(v, style: TextStyle(fontSize: big ? 26 : 21, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
