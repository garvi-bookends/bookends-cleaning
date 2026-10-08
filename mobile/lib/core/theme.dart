import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

/// Colours and building blocks from index.html's stylesheet.
class C {
  static const brand = Color(0xFF1E2A78);
  static const brand2 = Color(0xFF3B4FD8);
  static const brandMid = Color(0xFF2A3A9E);
  static const accent = Color(0xFFF2A93B);
  static const bg = Color(0xFFF3F5FB);
  static const card = Colors.white;
  static const line = Color(0xFFE0E4F0);
  static const ink = Color(0xFF0F1630);
  static const mut = Color(0xFF626C87);
  static const red = Color(0xFFE5484D);
  static const org = Color(0xFFF0664F);
  static const yel = Color(0xFFF5B52E);
  static const grn = Color(0xFF5F86C9); // the site's "green" is a blue
  static const blue = Color(0xFF3B7BF0);
  static const chev = Color(0xFFC2C8DC);

  static const headerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brand, brandMid, brand2],
    stops: [0, .55, 1],
  );
  static const btnGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand2, brand],
  );
}

Color scoreColor(int p) => p >= 90 ? C.grn : (p >= 75 ? C.yel : (p >= 60 ? C.org : C.red));
Color sevColor(int s) => [C.blue, C.yel, C.org, C.red][s.clamp(0, 3)];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.brand, primary: C.brand, surface: C.bg),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: C.line, width: 1.5)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: C.line, width: 1.5)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: C.brand2, width: 1.5)),
    ),
    dividerColor: C.line,
  );
}

// ---------------------------------------------------------------------------
// Pills
// ---------------------------------------------------------------------------
enum PillTone { red, org, yel, vio, grn, gry, blu }

const _pillColors = {
  PillTone.red: (Color(0xFFFDE8E9), Color(0xFFA3232B)),
  PillTone.org: (Color(0xFFFDE9E4), Color(0xFFA8341D)),
  PillTone.yel: (Color(0xFFFDF3D8), Color(0xFF8A5F00)),
  PillTone.vio: (Color(0xFFECE9FF), Color(0xFF4B3FB0)),
  PillTone.grn: (Color(0xFFE8F0FB), Color(0xFF3D5F9E)),
  PillTone.gry: (Color(0xFFECEEF7), Color(0xFF586280)),
  PillTone.blu: (Color(0xFFEEF2FF), Color(0xFF2A3A9E)),
};

class Pill extends StatelessWidget {
  final String text;
  final PillTone tone;
  const Pill(this.text, this.tone, {super.key});
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _pillColors[tone]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .2)),
    );
  }
}

// ---------------------------------------------------------------------------
// Ring gauge
// ---------------------------------------------------------------------------
class Ring extends StatelessWidget {
  final int pct;
  final double size, stroke;
  final bool light;
  const Ring(this.pct, {super.key, this.size = 76, this.stroke = 9, this.light = false});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(pct, stroke, light),
        child: Center(
          child: Text('$pct%',
              style: TextStyle(fontSize: size * .28, fontWeight: FontWeight.w800, color: light ? Colors.white : C.ink)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int pct;
  final double stroke;
  final bool light;
  _RingPainter(this.pct, this.stroke, this.light);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = light ? Colors.white.withValues(alpha: .22) : const Color(0xFFE6E9F4);
    canvas.drawArc(r, 0, 2 * pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = light ? Colors.white : scoreColor(pct);
    canvas.drawArc(r, -pi / 2, 2 * pi * pct.clamp(0, 100) / 100, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.pct != pct || o.light != light;
}

// ---------------------------------------------------------------------------
// Cards, sections, buttons
// ---------------------------------------------------------------------------
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color, border;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border, this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient: color == null
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF7F8FD)])
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? const Color(0xFFE3E7F3)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F1630), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F1E2A78), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}

class SecTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SecTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .9, color: C.mut)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

enum BtnKind { primary, sec, ok, no, warn }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool small, busy;
  const Btn(this.label, this.onTap, {super.key, this.kind = BtnKind.primary, this.small = false, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final grad = switch (kind) {
      BtnKind.primary => C.btnGradient,
      BtnKind.ok => const LinearGradient(colors: [Color(0xFF8FB0E6), C.grn]),
      BtnKind.no => const LinearGradient(colors: [Color(0xFFF0646A), C.red]),
      BtnKind.warn => const LinearGradient(colors: [Color(0xFFF78A6F), C.org]),
      BtnKind.sec => null,
    };
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: BoxConstraints(minHeight: small ? 44 : 56),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: grad,
            color: grad == null ? Colors.white : null,
            borderRadius: BorderRadius.circular(small ? 11 : 14),
            border: grad == null ? Border.all(color: C.line, width: 1.5) : null,
            boxShadow: grad == null ? null : const [BoxShadow(color: Color(0x381E2A78), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: grad == null ? C.brand : Colors.white, fontSize: small ? 14 : 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const AppChip(this.label, this.selected, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? C.btnGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? Colors.transparent : C.line, width: 1.5),
            boxShadow: selected ? const [BoxShadow(color: Color(0x401E2A78), blurRadius: 12, offset: Offset(0, 4))] : null,
          ),
          child: Text(label,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : C.mut)),
        ),
      );
}

class ChipRow extends StatelessWidget {
  final List<(String key, String label)> items;
  final String value;
  final ValueChanged<String> onChanged;
  const ChipRow(this.items, this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final (k, l) in items) AppChip(l, k == value, () => onChanged(k))]),
      );
}

class Stat extends StatelessWidget {
  final String value, label;
  final Color? color;
  final VoidCallback? onTap;
  const Stat(this.value, this.label, {super.key, this.color, this.onTap});
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color ?? C.ink)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              maxLines: 2,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.mut, letterSpacing: .3)),
        ]),
      );
}

/// A row of equal-width stat tiles that wraps on narrow screens.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  final int maxCols;
  const StatGrid(this.children, {super.key, this.maxCols = 3});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, c) {
        final cols = min(maxCols, max(2, (c.maxWidth / 110).floor()));
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.mut, letterSpacing: .3)),
      );
}

class Muted extends StatelessWidget {
  final String text;
  final double size;
  const Muted(this.text, {super.key, this.size = 13});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: size, color: C.mut));
}

class EmptyState extends StatelessWidget {
  final String emoji, text;
  const EmptyState(this.emoji, this.text, {super.key});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 14),
        child: Center(
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: C.mut)),
          ]),
        ),
      );
}

class InfoCard extends StatelessWidget {
  final Widget child;
  final Color bg, border;
  const InfoCard(this.child, {super.key, this.bg = const Color(0xFFFFF7E2), this.border = const Color(0xFFF6DFA3)});
  const InfoCard.red(this.child, {super.key})
      : bg = const Color(0xFFFDE8E9),
        border = const Color(0xFFF7C9CC);
  const InfoCard.warn(this.child, {super.key})
      : bg = const Color(0xFFFFF0EC),
        border = const Color(0xFFF8D3CA);
  const InfoCard.blue(this.child, {super.key})
      : bg = const Color(0xFFEEF2FF),
        border = const Color(0xFFD5DCF7);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, color: C.ink), child: child),
      );
}

/// A list row with optional leading tile and trailing chevron.
class LRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? sub;
  final List<Widget> pills;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? extra;
  const LRow({super.key, this.leading, required this.title, this.sub, this.pills = const [], this.trailing, this.onTap, this.extra});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: const TextStyle(fontSize: 12.5, color: C.mut)),
                ],
                if (pills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: pills),
                ],
                if (extra != null) ...[const SizedBox(height: 4), extra!],
              ]),
            ),
            trailing ?? (onTap != null ? const Text('›', style: TextStyle(fontSize: 26, color: C.chev)) : const SizedBox()),
          ]),
        ),
      );
}

class Tile extends StatelessWidget {
  final String emoji;
  final Color bg;
  final double size;
  const Tile(this.emoji, this.bg, {super.key, this.size = 46});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .24)),
        child: Text(emoji, style: TextStyle(fontSize: size * .48)),
      );
}

/// Cards that hold rows separated by thin lines.
class RowsCard extends StatelessWidget {
  final List<Widget> rows;
  const RowsCard(this.rows, {super.key});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: C.line),
              rows[i],
            ]
          ]),
        ),
      );
}

class KV extends StatelessWidget {
  final String k;
  final Widget v;
  const KV(this.k, this.v, {super.key});
  KV.text(this.k, String value, {super.key, bool bold = false})
      : v = Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500));
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: C.mut, fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: v),
        ]),
      );
}

class Bar extends StatelessWidget {
  final String label;
  final int pct;
  const Bar(this.label, this.pct, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('$pct%', style: TextStyle(fontWeight: FontWeight.w800, color: scoreColor(pct))),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE6E9F4),
              color: scoreColor(pct),
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Toast, sheets, dialogs
// ---------------------------------------------------------------------------
final scaffoldKey = GlobalKey<ScaffoldMessengerState>();

void toast(String msg) {
  scaffoldKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      duration: const Duration(milliseconds: 2300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
    ));
}

/// Bottom sheet with the site's ✕ + title header. On wide screens it is a
/// centred dialog instead.
Future<T?> showSheet<T>(BuildContext context, String title, Widget Function(BuildContext) body) {
  final wide = MediaQuery.of(context).size.width >= 900;
  Widget frame(BuildContext ctx) => Container(
        color: C.bg,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFE3E7F2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.close, size: 20, color: C.ink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: body(ctx),
            ),
          ),
        ]),
      );
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: C.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820), child: frame(ctx)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .94),
    builder: frame,
  );
}

Future<bool> askConfirm(BuildContext context, String title, String message, String ok, {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 14.5, color: C.mut)),
      actions: [
        Row(children: [
          Expanded(child: Btn('Cancel', () => Navigator.pop(ctx, false), kind: BtnKind.sec, small: true)),
          const SizedBox(width: 10),
          Expanded(child: Btn(ok, () => Navigator.pop(ctx, true), kind: danger ? BtnKind.no : BtnKind.primary, small: true)),
        ]),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext context, String title, String message,
    {String initial = '', String hint = '', String ok = 'OK', bool danger = false}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: const TextStyle(fontSize: 14.5, color: C.mut)),
        const SizedBox(height: 12),
        TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
      ]),
      actions: [
        Row(children: [
          Expanded(child: Btn('Cancel', () => Navigator.pop(ctx), kind: BtnKind.sec, small: true)),
          const SizedBox(width: 10),
          Expanded(child: Btn(ok, () => Navigator.pop(ctx, c.text), kind: danger ? BtnKind.no : BtnKind.primary, small: true)),
        ]),
      ],
    ),
  );
  return r;
}

/// A photo that may be an http URL or a data: URL kept on the phone.
class Photo extends StatelessWidget {
  final String? src;
  final double? width, height;
  final BoxFit fit;
  final double radius;
  const Photo(this.src, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius = 11});
  @override
  Widget build(BuildContext context) {
    final s = src;
    Widget img;
    if (s == null || s.isEmpty) {
      img = Container(color: const Color(0xFFECEEF7));
    } else if (s.startsWith('data:')) {
      img = Image.memory(
        base64Decode(s.substring(s.indexOf(',') + 1)),
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: C.mut),
      );
    } else {
      img = Image.network(s, width: width, height: height, fit: fit,
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: C.mut)));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: width, height: height, child: img));
  }
}

void showPhotoViewer(BuildContext context, String src) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(maxScale: 5, child: Center(child: Photo(src, fit: BoxFit.contain, radius: 0))),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 30,
          child: Text('Pinch the photo to zoom · tap to close',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ]),
    ),
  );
}
