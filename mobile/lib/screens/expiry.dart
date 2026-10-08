import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/photo.dart';
import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'labels.dart';
import 'shell.dart';

PillTone _statusTone(String k) => k == 'expired' ? PillTone.red : (k == 'soon' ? PillTone.org : PillTone.grn);

class ProductRow extends StatelessWidget {
  final Rec p;
  final bool showLoc;
  const ProductRow(this.p, {super.key, this.showLoc = false});
  @override
  Widget build(BuildContext context) {
    final (k, label) = expiryStatus(p['expiry'] as String?);
    return LRow(
      leading: p['photo'] != null ? Photo(p['photo'] as String, width: 46, height: 46) : const Tile('📦', Color(0xFFFFF7E2)),
      title: '${p['name']}',
      sub: [
        if (showLoc) locById(p['loc'] as String?)?.name ?? '',
        'MFG ${fmtD(p['opened'] as String?)}',
        'Exp ${fmtD(p['expiry'] as String?)} · ${relDays(p['expiry'] as String?)}',
      ].where((x) => x.isNotEmpty).join(' · '),
      pills: [Pill(label, _statusTone(k)), if (!isActive(p)) const Pill('INACTIVE', PillTone.gry)],
      onTap: () => productSheet(context, p['id'] as String),
    );
  }
}

class ExpiryScreen extends StatefulWidget {
  const ExpiryScreen({super.key});
  @override
  State<ExpiryScreen> createState() => _ExpiryScreenState();
}

class _ExpiryScreenState extends State<ExpiryScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    context.watch<Store>();
    final nav = context.watch<Nav>();
    final loc = S.loc;
    var f = nav.expFilter;
    if (f == 'month' || f == 'safe') f = 'active';
    final all = productsFor(loc);
    final st = expiryStats(loc);
    int n(String k) => all.where((p) => expiryStatus(p['expiry'] as String?).$1 == k).length;
    final ql = q.toLowerCase();
    final shown = all.where((p) {
      if (f != 'all' && expiryStatus(p['expiry'] as String?).$1 != f) return false;
      if (ql.isEmpty) return true;
      return '${p['name']} ${p['cat'] ?? ''} ${p['batch'] ?? ''} ${locById(p['loc'] as String?)?.name ?? ''}'.toLowerCase().contains(ql);
    }).toList()
      ..sort((a, b) => '${a['expiry']}'.compareTo('${b['expiry']}'));

    return Column(children: [
      PageHeader('EXPIRY DATE', sub: locName(loc)),
      Expanded(
        child: PageBody(
          fab: S.perm.readonly ? null : Fab('＋ Add Expiry Date', () => productForm(context, null, noun: 'expiry date')),
          children: [
            StatGrid([
              Stat('${all.length}', 'Items'),
              Stat('${n('active')}', 'Active', color: C.grn),
              Stat('${n('soon')}', 'Expiring soon', color: n('soon') > 0 ? C.org : C.mut),
              Stat('${n('expired')}', 'Expired', color: n('expired') > 0 ? C.red : C.mut),
            ], maxCols: 4),
            const SizedBox(height: 10),
            if (st.expired > 0 || st.soon > 0)
              InfoCard.warn(Text(
                '⚠️ ${st.expired > 0 ? '${st.expired} expired item${st.expired > 1 ? 's' : ''} must be discarded now. ' : ''}'
                '${st.soon > 0 ? '${st.soon} item${st.soon > 1 ? 's' : ''} expire within 7 days.' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )),
            const FieldLabel('Search'),
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Item or category', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => scanSheet(context),
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan a label',
              ),
            ]),
            const SizedBox(height: 12),
            ChipRow([
              ('all', 'All ${all.length}'),
              ('active', 'Active ${n('active')}'),
              ('soon', 'Expiring soon ${n('soon')}'),
              ('expired', 'Expired ${n('expired')}'),
            ], f, (k) => setState(() => nav.expFilter = k)),
            SecTitle('Items · ${shown.length}${shown.length != all.length ? ' of ${all.length}' : ''}'),
            if (shown.isEmpty)
              EmptyState('📦', q.isNotEmpty ? 'Nothing matches “$q”' : 'No items in this view')
            else
              RowsCard([for (final p in shown) ProductRow(p, showLoc: loc == 'ALL')]),
          ],
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Product sheet
// ---------------------------------------------------------------------------
void productSheet(BuildContext context, String id) {
  showSheet(context, 'Product', (ctx) {
    return Consumer<Store>(builder: (ctx, _, _) {
      final p = S.products[id];
      if (p == null) return const EmptyState('📦', 'This product is no longer here');
      final e = expiryState(p['expiry'] as String?);
      final mayEdit = !S.perm.readonly && (S.perm.all || S.me?['loc'] == p['loc']);
      final stateText = e.k == 'expired'
          ? 'EXPIRED ${-e.days}d AGO'
          : (e.k == 'safe' ? 'SAFE · ${e.days}d LEFT' : e.label);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (p['photo'] != null) ...[
                GestureDetector(
                    onTap: () => showPhotoViewer(ctx, p['photo'] as String),
                    child: Photo(p['photo'] as String, width: 78, height: 78)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Muted('${(p['cat'] ?? '') != '' ? '${p['cat']} · ' : ''}${locName(p['loc'] as String?)}'),
                  const SizedBox(height: 6),
                  Pill('${e.emoji} $stateText', e.k == 'expired' ? PillTone.red : (e.k == 'soon' ? PillTone.org : (e.k == 'month' ? PillTone.yel : PillTone.grn))),
                ]),
              ),
            ]),
            const Divider(height: 22),
            KV.text('MFG date', fmtD(p['opened'] as String?)),
            KV.text('Expiry date', '${fmtD(p['expiry'] as String?)} · ${relDays(p['expiry'] as String?)}'),
            KV.text('Added by', uname(p['by'] as String?)),
            KV.text('Label', p['labelled'] == true ? '✓ applied ${fmtDT((p['labelledAt'] as num?)?.toInt())}' : 'not written yet'),
            KV.text('Code', labelCode(p)),
          ]),
        ),
        if (e.k == 'expired') ...[
          const SizedBox(height: 10),
          const InfoCard.red(Text('🔴 Do not use. Discard and record wastage.', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
        const SizedBox(height: 12),
        if (mayEdit) ...[
          if (p['labelled'] != true) ...[
            Btn('✓ I have written it and stuck it on', () => markLabelled(ctx, p), kind: BtnKind.ok),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(child: Btn('Edit', () {
              Navigator.pop(ctx);
              productForm(context, id);
            }, kind: BtnKind.sec)),
            const SizedBox(width: 10),
            Expanded(
              child: Btn('Discard / remove', () async {
                if (!await askConfirm(ctx, 'Remove ${p['name']}?', 'Use this when the item has been used up or thrown away.',
                    'Remove',
                    danger: true)) {
                  return;
                }
                S.remove('products', p);
                if (ctx.mounted) Navigator.pop(ctx);
                toast('Product removed');
              }, kind: BtnKind.no),
            ),
          ]),
        ],
      ]);
    });
  });
}

// ---------------------------------------------------------------------------
// Add / edit form
// ---------------------------------------------------------------------------
void productForm(BuildContext context, String? id, {String? noun}) {
  final p = id == null ? null : S.products[id];
  final tab = navState.tab;
  final n = noun ?? (tab == 'exp' ? 'expiry date' : 'label');
  String loc = p?['loc'] as String? ?? S.loc;
  if (loc == 'ALL') {
    final v = visibleLocations();
    loc = (S.me?['loc'] as String?) ?? (v.isNotEmpty ? v.first : kLocations.first.id);
  }
  showSheet(context, p != null ? 'Edit $n' : 'Add $n · ${locName(loc)}', (ctx) => _ProductForm(p, loc));
}

class _ProductForm extends StatefulWidget {
  final Rec? p;
  final String loc;
  const _ProductForm(this.p, this.loc);
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final TextEditingController name;
  late String opened, expiry, code;
  late String loc;
  String? photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.p;
    loc = widget.loc;
    name = TextEditingController(text: (p?['name'] ?? '') as String);
    opened = (p?['opened'] as String?) ?? ymd(today());
    expiry = (p?['expiry'] as String?) ?? ymd(addDays(today(), 3));
    photo = p?['photo'] as String?;
    code = p != null ? labelCode(p) : newProductId(loc);
  }

  Future<void> _pick(bool isOpened) async {
    final cur = tryParseD(isOpened ? opened : expiry) ?? today();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2023), lastDate: DateTime(2035));
    if (d != null) setState(() => isOpened ? opened = ymd(d) : expiry = ymd(d));
  }

  Future<void> _shoot(bool camera) async {
    setState(() => _busy = true);
    try {
      final b = await PhotoTool.capture(
          stamp: '${fmtDT(DateTime.now().millisecondsSinceEpoch)}  ·  ${initials(S.me?['name'] as String?)}', camera: camera);
      if (b != null) {
        final url = await S.storePhoto(b, loc);
        setState(() => photo = url);
      }
    } catch (_) {
      toast('That photo could not be read — try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final nm = name.text.trim();
    if (nm.isEmpty) return toast('Enter a name');
    if (opened.isEmpty) return toast('Enter the MFG date');
    if (expiry.isEmpty) return toast('Enter the expiry date');
    if (expiry.compareTo(opened) < 0) return toast('Expiry cannot be before the MFG date');
    final p = widget.p;
    if (p != null) {
      p
        ..['name'] = nm
        ..['opened'] = opened
        ..['expiry'] = expiry
        ..['photo'] = photo;
      S.touch('products', p);
      S.logAct('product', 'Updated: $nm', p['loc'] as String?);
      Navigator.pop(context);
      toast('Label updated');
      return;
    }
    while (S.products.values.any((x) => labelCode(x).toUpperCase() == code)) {
      code = newProductId(loc);
    }
    final r = <String, dynamic>{
      'id': code,
      'loc': loc,
      'name': nm,
      'code': code,
      'opened': opened,
      'expiry': expiry,
      'cat': '',
      'type': '',
      'desc': '',
      'color': '',
      'status': 'Active',
      'batch': '',
      'qty': 1,
      'unit': 'kg',
      'storage': '',
      'note': '',
      'photo': photo,
      'labelled': false,
      'labelledAt': null,
      'by': S.myId,
      'initials': initials(S.me?['name'] as String?),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    S.touch('products', r);
    S.logAct('product', 'Added: $nm', loc);
    Navigator.pop(context);
    toast('Added');
    Future.delayed(const Duration(milliseconds: 250), () {
      final c = navigatorContext;
      if (c != null && c.mounted) labelSheet(c, code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final (k, label) = expiryStatus(expiry);
    final life = daysBetween(opened, expiry);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const FieldLabel('Name'),
      TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Fresh Paneer'), textCapitalization: TextCapitalization.sentences),
      Row(children: [
        Expanded(child: _date('MFG date', opened, () => _pick(true))),
        const SizedBox(width: 8),
        Expanded(child: _date('Expiry date', expiry, () => _pick(false))),
      ]),
      const SizedBox(height: 10),
      Wrap(children: [
        for (final d in [1, 2, 3, 5, 7, 14, 30])
          AppChip('+${d}d', daysBetween(opened, expiry) == d, () {
            final base = tryParseD(opened) ?? today();
            setState(() => expiry = ymd(addDays(base, d)));
          }),
      ]),
      const Muted('Tap a chip to set the expiry that many days after the MFG date.', size: 12),
      const FieldLabel('Photo (optional)'),
      GestureDetector(
        onTap: _busy ? null : () => photo == null ? _shoot(true) : showPhotoViewer(context, photo!),
        child: Container(
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: photo == null ? Colors.white : const Color(0xFF101413),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.chev, width: 2),
          ),
          child: _busy
              ? const CircularProgressIndicator()
              : photo == null
                  ? const Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('📷', style: TextStyle(fontSize: 34)),
                      Text('TAP TO TAKE PHOTO', style: TextStyle(fontWeight: FontWeight.w800, color: C.mut)),
                    ])
                  : Photo(photo, fit: BoxFit.contain, radius: 14),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Btn('📷 Take photo', () => _shoot(true), kind: BtnKind.sec, small: true)),
        const SizedBox(width: 8),
        Expanded(child: Btn('🖼 Upload photo', () => _shoot(false), kind: BtnKind.sec, small: true)),
      ]),
      if (photo != null)
        TextButton(onPressed: () => setState(() => photo = null), child: const Text('Remove photo', style: TextStyle(color: C.red))),
      const SecTitle('Label'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Pill(label, _statusTone(k)), const Spacer(), Muted(relDays(expiry))]),
          const SizedBox(height: 6),
          Text(life < 0
              ? '${fmtD(opened)} → ${fmtD(expiry)} · use-by is before the opened date'
              : '${fmtD(opened)} → ${fmtD(expiry)} · $life day shelf life'),
          const SizedBox(height: 6),
          if (widget.p != null)
            Row(children: [
              Expanded(
                  child: Text(widget.p!['labelled'] == true
                      ? '✓ Label applied ${fmtDT((widget.p!['labelledAt'] as num?)?.toInt())}'
                      : '✕ Label not written yet')),
              widget.p!['labelled'] == true
                  ? const Pill('LABEL OK', PillTone.grn)
                  : const Pill('LABEL MISSING', PillTone.red),
            ])
          else
            const Muted('Saving records it'),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Btn('Cancel', () => Navigator.pop(context), kind: BtnKind.sec)),
        const SizedBox(width: 10),
        Expanded(child: Btn(widget.p != null ? 'Save changes' : 'Done', _save, busy: _busy)),
      ]),
    ]);
  }

  Widget _date(String label, String v, VoidCallback onTap) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(label),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: C.line, width: 1.5)),
            child: Row(children: [
              Expanded(child: Text(fmtD(v), style: const TextStyle(fontWeight: FontWeight.w600))),
              const Icon(Icons.calendar_today_outlined, size: 18, color: C.mut),
            ]),
          ),
        ),
      ]);
}

/// A context below the Navigator, for opening a sheet after one closes.
final navKey = GlobalKey<NavigatorState>();
BuildContext? get navigatorContext => navKey.currentContext;

// ---------------------------------------------------------------------------
// Scan a label
// ---------------------------------------------------------------------------
String? parseLabelCode(String text) {
  final raw = text.trim();
  String? id;
  final m = RegExp(r'#p=([A-Za-z0-9-]+)').firstMatch(raw);
  if (m != null) {
    id = m.group(1);
  } else if (raw.startsWith('BOOKENDS|')) {
    id = raw.split('|').elementAtOrNull(1);
  } else if (raw.startsWith('BK|')) {
    id = raw.split('|').elementAtOrNull(2);
  } else {
    id = raw;
  }
  return id?.trim().toUpperCase();
}

void scanSheet(BuildContext context) {
  final ctrl = TextEditingController();
  var done = false;
  void handle(BuildContext ctx, String text) {
    if (done) return;
    final id = parseLabelCode(text) ?? '';
    final p = S.products.values.where((x) => x['id'] == id || labelCode(x).toUpperCase() == id).firstOrNull;
    done = true;
    Navigator.pop(ctx);
    if (p != null) {
      if (S.perm.all) S.loc = p['loc'] as String;
      productSheet(context, p['id'] as String);
      toast('Scanned ${p['name']}');
    } else {
      toast('No product found for $id');
    }
  }

  showSheet(context, 'Scan label QR', (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: MobileScanner(
              onDetect: (cap) {
                final v = cap.barcodes.firstOrNull?.rawValue;
                if (v != null) handle(ctx, v);
              },
              errorBuilder: (c, e) => Container(
                color: Colors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                child: const Text('The camera could not be started. Allow camera access in Settings, or type the label code below.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(child: Muted('Point at the label QR…')),
        const FieldLabel('Or type the label code'),
        TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'e.g. P-CPP-03'), onSubmitted: (v) => handle(ctx, v)),
        const SizedBox(height: 10),
        Btn('Find product', () => handle(ctx, ctrl.text)),
      ]));
}
