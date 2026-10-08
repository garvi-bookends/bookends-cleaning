/// Date helpers matching index.html (ymd, weekId, fmtD, …). All local time.
library;

const kMon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String pad2(int n) => n.toString().padLeft(2, '0');

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String ymd(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';

DateTime parseD(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime? tryParseD(String? s) {
  if (s == null || s.length < 10) return null;
  try {
    return parseD(s.substring(0, 10));
  } catch (_) {
    return null;
  }
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int daysBetween(String a, String b) {
  final da = tryParseD(a), db = tryParseD(b);
  if (da == null || db == null) return 0;
  return (db.difference(da).inHours / 24).round();
}

DateTime mondayOf(DateTime d) => addDays(DateTime(d.year, d.month, d.day), -((d.weekday + 6) % 7));

String weekId(DateTime d) {
  final m = mondayOf(d);
  final t = addDays(m, 3);
  final jan1 = DateTime(t.year, 1, 1);
  final wk = (((t.difference(jan1).inHours / 24).round() + 1) / 7).ceil();
  return '${t.year}-W${pad2(wk)}';
}

DateTime weekStart(String wid) {
  final p = wid.split('-W');
  final y = int.parse(p[0]), w = int.parse(p[1]);
  return addDays(mondayOf(DateTime(y, 1, 4)), (w - 1) * 7);
}

String monthId(DateTime d) => '${d.year}-${pad2(d.month)}';
String monthOfWeek(String wid) => monthId(addDays(weekStart(wid), 3));

String fmtD(String? s) {
  final d = tryParseD(s);
  if (d == null) return '—';
  return '${pad2(d.day)} ${kMon[d.month - 1]} ${pad2(d.year % 100)}';
}

String fmtDT(int? ms) {
  if (ms == null || ms == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${pad2(d.day)} ${kMon[d.month - 1]}, ${pad2(d.hour)}:${pad2(d.minute)}';
}

String fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h12:${pad2(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String weekLabel(String wid) {
  final m = weekStart(wid);
  return '${fmtD(ymd(m))} – ${fmtD(ymd(addDays(m, 6)))}';
}

List<String> recentWeeks(int n) {
  final t = today();
  return [for (var i = 0; i < n; i++) weekId(addDays(t, -7 * i))];
}

/// "{n} days ago" / "today" / "{n} days left"
String relDays(String? expiry) {
  if (expiry == null) return '';
  final d = daysBetween(ymd(today()), expiry);
  if (d == 0) return 'today';
  if (d < 0) return '${-d} day${d == -1 ? '' : 's'} ago';
  return '$d day${d == 1 ? '' : 's'} left';
}

/// IST helpers for the daily checklists (fixed +05:30).
const kIstOffset = Duration(minutes: 330);
DateTime istNow() => DateTime.now().toUtc().add(kIstOffset);
String istYmd([DateTime? utcInstant]) {
  final d = (utcInstant ?? DateTime.now().toUtc()).toUtc().add(kIstOffset);
  return '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
}

String fmtIstTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(kIstOffset);
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h12:${pad2(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}
