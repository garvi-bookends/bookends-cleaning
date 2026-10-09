import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import 'constants.dart';

typedef Rec = Map<String, dynamic>;

/// Everything the app keeps on the phone, plus the cloud sync.
///
/// Mirrors the website's DB + Cloud objects: records are plain JSON maps (so
/// fields this app does not know about survive a round trip), edits are
/// stamped with `_u` and pushed ~1 s later, other phones' edits are pulled
/// every 45 s, and the newest `_u` wins.
class Store extends ChangeNotifier {
  Store._();
  static final Store I = Store._();

  static const kinds = ['tasks', 'products'];

  // ---- session ----
  Rec? me;
  bool offline = false;
  String defaultPassword = '1234';
  int minPasswordLength = 8;

  // ---- data ----
  List<Rec> users = [];
  final Map<String, Map<String, Rec>> data = {'tasks': {}, 'products': {}};
  Map<String, Rec> checklist = {};
  List<Rec> jobTypes = [];
  Map<String, int> read = {};
  List<Rec> log = [];

  // ---- sync state ----
  String? owner;
  String epoch = '';
  Map<String, String?> cursor = {'tasks': null, 'products': null};
  Map<String, Map<String, int>> dirty = {'tasks': {}, 'products': {}};
  Map<String, Map<String, String?>> tombs = {'tasks': {}, 'products': {}};
  String syncState = 'idle'; // idle | syncing | error | offline
  String? syncError;
  DateTime? lastSync;
  int held = 0;

  // ---- UI state shared across tabs ----
  String loc = 'ALL';

  Map<String, Rec> get tasks => data['tasks']!;
  Map<String, Rec> get products => data['products']!;
  Role get perm => roleOf(me?['role'] as String?);
  String get myId => (me?['id'] ?? '') as String;

  File? _file;
  Timer? _pushTimer, _pollTimer, _saveTimer;
  StreamSubscription? _net;
  bool _syncing = false, _again = false;

  // ------------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------------
  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/bookends_db.json');
    try {
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        users = _list(j['users']);
        for (final k in kinds) {
          data[k] = {for (final r in _list(j[k])) r['id'] as String: r};
        }
        checklist = (j['checklist'] as Map?)?.map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v))) ?? {};
        jobTypes = _list(j['jobTypes']);
        read = (j['read'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ?? {};
        log = _list(j['log']);
        final s = (j['sync'] as Map?) ?? {};
        owner = s['owner'] as String?;
        epoch = (s['epoch'] ?? '') as String;
        cursor = Map<String, String?>.from((s['cursor'] as Map?) ?? cursor);
        dirty = {
          for (final k in kinds)
            k: Map<String, int>.from(((s['dirty'] as Map?)?[k] as Map?)?.map((a, b) => MapEntry(a as String, 1)) ?? {})
        };
        tombs = {for (final k in kinds) k: Map<String, String?>.from(((s['tombs'] as Map?)?[k] as Map?) ?? {})};
        me = (j['me'] as Map?)?.cast<String, dynamic>();
      }
    } catch (e) {
      debugPrint('[store] could not read saved data: $e');
    }
  }

  static List<Rec> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : <Rec>[];

  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _writeNow);
    notifyListeners();
  }

  Future<void> _writeNow() async {
    final f = _file;
    if (f == null) return;
    pruneLog();
    final j = {
      'me': me,
      'users': users,
      for (final k in kinds) k: data[k]!.values.toList(),
      'checklist': checklist,
      'jobTypes': jobTypes,
      'read': read,
      'log': log,
      'sync': {'owner': owner, 'epoch': epoch, 'cursor': cursor, 'dirty': dirty, 'tombs': tombs},
    };
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(j));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('[store] save failed: $e');
    }
  }

  Future<void> wipeLocal() async {
    for (final k in kinds) {
      data[k]!.clear();
      dirty[k]!.clear();
      tombs[k]!.clear();
      cursor[k] = null;
    }
    save();
  }

  // ------------------------------------------------------------------
  // Activity log (device only, 30 days / 2000 entries)
  // ------------------------------------------------------------------
  void logAct(String type, String text, [String? at]) {
    log.insert(0, {'t': DateTime.now().millisecondsSinceEpoch, 'type': type, 'text': text, 'loc': at, 'by': me?['id']});
    save();
  }

  void pruneLog() {
    final cut = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    log.removeWhere((e) => ((e['t'] as num?) ?? 0) < cut);
    if (log.length > 2000) log = log.sublist(0, 2000);
  }

  // ------------------------------------------------------------------
  // Session
  // ------------------------------------------------------------------
  Future<void> adoptUser(Rec user) async {
    me = user;
    if (owner != user['id']) {
      owner = user['id'] as String?;
      cursor = {'tasks': null, 'products': null};
    }
    if (loc == 'ALL' || !perm.all) loc = (user['loc'] as String?) ?? 'ALL';
    if (!perm.all && loc == 'ALL') loc = kLocations.first.id;
    save();
  }

  Future<void> loadConfig() async {
    try {
      final c = await Api.I.get('/api/config', auth: false);
      defaultPassword = (c['defaultPassword'] ?? defaultPassword).toString();
      minPasswordLength = (c['minPasswordLength'] as num?)?.toInt() ?? minPasswordLength;
    } catch (_) {}
  }

  Future<void> loadRoster() async {
    try {
      final r = await Api.I.get('/api/users/roster');
      users = _list(r['users']);
      save();
    } catch (_) {}
  }

  Future<void> signOut() async {
    stop();
    await Api.I.logout();
    me = null;
    offline = false;
    final p = await SharedPreferences.getInstance();
    await p.remove('bk_last_loc');
    save();
  }

  // ------------------------------------------------------------------
  // Records
  // ------------------------------------------------------------------
  /// Save an edit: stamp it, mark it dirty, push soon.
  void touch(String kind, Rec obj) {
    obj['_u'] = DateTime.now().millisecondsSinceEpoch;
    data[kind]![obj['id'] as String] = obj;
    dirty[kind]![obj['id'] as String] = 1;
    save();
    schedulePush();
  }

  /// Queue without re-stamping (generated jobs keep _u 0 so a server copy wins).
  void queue(String kind, Rec obj) {
    data[kind]![obj['id'] as String] = obj;
    dirty[kind]![obj['id'] as String] = 1;
  }

  void remove(String kind, Rec obj) {
    final id = obj['id'] as String;
    data[kind]!.remove(id);
    dirty[kind]!.remove(id);
    tombs[kind]![id] = obj['loc'] as String?;
    save();
    schedulePush();
  }

  // ------------------------------------------------------------------
  // Sync
  // ------------------------------------------------------------------
  bool get canSync => me != null && Api.I.accessToken != null && me?['mustChange'] != true;

  int get waiting => kinds.fold(0, (n, k) => n + dirty[k]!.length + tombs[k]!.length);

  String get syncLabel {
    if (syncState == 'syncing') return 'Syncing…';
    if (syncState == 'offline') return 'Offline — ${waiting > 0 ? '$waiting waiting to upload' : 'work is saved on this phone'}';
    if (syncState == 'error') return 'Sync problem';
    if (held > 0) return '$held job${held == 1 ? ' is' : 's are'} waiting for a photo to upload — not on the server yet';
    if (waiting > 0) return '$waiting waiting to upload';
    return 'All devices in sync';
  }

  void start() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) => sync());
    _net ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) sync();
    });
    sync();
    Future.delayed(const Duration(seconds: 3), retryPhotoUploads);
  }

  void stop() {
    _pollTimer?.cancel();
    _pushTimer?.cancel();
    _net?.cancel();
    _net = null;
  }

  void schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 900), () => sync(pullToo: false));
  }

  /// Pull then push. Concurrent calls collapse into one follow-up run.
  Future<void> sync({bool pullToo = true}) async {
    if (!canSync) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    syncState = 'syncing';
    notifyListeners();
    try {
      if (pullToo) {
        final first = cursor['tasks'] == null && cursor['products'] == null;
        for (final k in kinds) {
          await _pull(k, first);
        }
      }
      for (final k in kinds) {
        await _push(k);
      }
      if (pullToo) await pullChecklist();
      syncState = 'idle';
      syncError = null;
      lastSync = DateTime.now();
      onSynced?.call();
    } on ApiException catch (e) {
      if (e.code == 'DATA_WIPED') {
        await _adoptEpoch((e.body['epoch'] ?? '') as String);
        _again = true;
      } else {
        syncState = e.isOffline ? 'offline' : 'error';
        syncError = e.message;
      }
    } catch (e) {
      syncState = 'error';
      syncError = '$e';
    } finally {
      _syncing = false;
      save();
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    }
    if (pullToo) unawaited(retryPhotoUploads());
  }

  /// Called after every successful sync (generate jobs etc).
  VoidCallback? onSynced;

  Future<void> _adoptEpoch(String e) async {
    epoch = e;
    for (final k in kinds) {
      data[k]!.clear();
      dirty[k]!.clear();
      tombs[k]!.clear();
      cursor[k] = null;
    }
    save();
  }

  Future<void> _pull(String kind, bool first) async {
    var since = cursor[kind] ?? '1970-01-01T00:00:00Z';
    String? after;
    while (true) {
      final q = {'since': since, if (after != null) 'after': after};
      final r = await Api.I.get('/api/sync/$kind', query: q);
      final e = (r['epoch'] ?? '') as String;
      if (e != epoch) {
        // Only a change from a known epoch means the server was wiped; the
        // first epoch this phone ever sees is simply adopted.
        if (epoch.isNotEmpty) {
          await _adoptEpoch(e);
          return _pull(kind, true);
        }
        epoch = e;
      }
      for (final row in _list(r['rows'])) {
        _merge(kind, row, first);
      }
      if (r['more'] == true) {
        since = r['next']['since'] as String;
        after = r['next']['after'] as String?;
        continue;
      }
      cursor[kind] = r['cursor'] as String?;
      break;
    }
  }

  void _merge(String kind, Rec row, bool first) {
    final remote = Map<String, dynamic>.from(row['data'] as Map);
    final id = row['id'] as String;
    final rt = (remote['_u'] as num?)?.toInt() ??
        DateTime.tryParse((row['updated_at'] ?? '') as String)?.millisecondsSinceEpoch ??
        0;
    final local = data[kind]![id];
    if (remote['deleted'] == true) {
      data[kind]!.remove(id);
      dirty[kind]!.remove(id);
      return;
    }
    if (local == null) {
      remote['_u'] = rt;
      data[kind]![id] = remote;
      return;
    }
    final lu = (local['_u'] as num?)?.toInt() ?? 0;
    if (dirty[kind]!.containsKey(id)) {
      if (lu >= rt) return;
      dirty[kind]!.remove(id);
    }
    if (first || rt > lu) {
      remote['_u'] = rt;
      data[kind]![id] = remote;
    }
  }

  static const _chunkBytes = 700 * 1024, _chunkRows = 150;

  Future<void> _push(String kind) async {
    if (perm.readonly) {
      dirty[kind]!.clear();
      tombs[kind]!.clear();
      return;
    }
    final rows = <Rec>[];
    final sentU = <String, int>{};
    var heldNow = 0;
    for (final id in dirty[kind]!.keys.toList()) {
      final o = data[kind]![id];
      if (o == null) {
        dirty[kind]!.remove(id);
        continue;
      }
      final row = {'id': id, 'loc': o['loc'], 'data': o};
      if (jsonEncode(row).length > _chunkBytes) {
        heldNow++;
        continue;
      }
      sentU[id] = (o['_u'] as num?)?.toInt() ?? 0;
      rows.add(row);
    }
    final tombIds = tombs[kind]!.keys.toList();
    for (final id in tombIds) {
      rows.add({
        'id': id,
        'loc': tombs[kind]![id],
        'data': {'id': id, 'deleted': true, '_u': DateTime.now().millisecondsSinceEpoch},
      });
    }
    if (kind == 'tasks') held = heldNow;

    var i = 0;
    while (i < rows.length) {
      final chunk = <Rec>[];
      var bytes = 0;
      while (i < rows.length && chunk.length < _chunkRows) {
        final b = jsonEncode(rows[i]).length;
        if (chunk.isNotEmpty && bytes + b > _chunkBytes) break;
        chunk.add(rows[i]);
        bytes += b;
        i++;
      }
      Map<String, dynamic> r;
      try {
        r = await Api.I.post('/api/sync/$kind', {'rows': chunk, 'epoch': epoch});
      } on ApiException catch (e) {
        if (e.code == 'READ_ONLY') {
          dirty[kind]!.clear();
          tombs[kind]!.clear();
          return;
        }
        rethrow;
      }
      for (final row in chunk) {
        final id = row['id'] as String;
        if ((row['data'] as Map)['deleted'] == true) {
          tombs[kind]!.remove(id);
        } else if (((data[kind]![id]?['_u'] as num?)?.toInt() ?? -1) == sentU[id]) {
          dirty[kind]!.remove(id);
        }
      }
      for (final c in _list(r['current'])) {
        dirty[kind]!.remove(c['id']);
        _merge(kind, c, true);
      }
    }
  }

  Future<void> pullChecklist() async {
    try {
      final items = await Api.I.get('/api/checklist/items');
      final list = _list(items['items']);
      checklist = {for (final it in list) it['tkey'] as String: it};
    } catch (_) {}
    try {
      final t = await Api.I.get('/api/checklist/types');
      jobTypes = _list(t['types']);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Photos
  // ------------------------------------------------------------------
  static bool isDataUrl(dynamic v) => v is String && v.startsWith('data:');

  static Uint8List? dataUrlBytes(String v) {
    final i = v.indexOf(',');
    if (i < 0) return null;
    try {
      return base64Decode(v.substring(i + 1));
    } catch (_) {
      return null;
    }
  }

  static String toDataUrl(Uint8List jpeg) => 'data:image/jpeg;base64,${base64Encode(jpeg)}';

  bool _uploading = false;

  /// Upload photos still kept on the phone as data: URLs, one at a time.
  Future<void> retryPhotoUploads() async {
    if (_uploading || !canSync || perm.readonly) return;
    _uploading = true;
    var changed = false;
    try {
      final jobs = <(String, Rec, String)>[];
      for (final t in tasks.values) {
        for (final f in ['before', 'after']) {
          if (isDataUrl(t[f])) jobs.add(('tasks', t, f));
        }
      }
      for (final p in products.values) {
        if (isDataUrl(p['photo'])) jobs.add(('products', p, 'photo'));
      }
      for (final (kind, rec, field) in jobs) {
        final v = rec[field] as String;
        final bytes = dataUrlBytes(v);
        if (bytes == null) continue;
        try {
          final url = await Api.I.uploadPhoto(bytes, (rec['loc'] ?? 'misc') as String);
          final cur = data[kind]![rec['id']];
          if (cur != null && cur[field] == v) {
            cur[field] = url;
            touch(kind, cur);
            changed = true;
          }
        } on ApiException catch (e) {
          if (e.code == 'NOT_AN_IMAGE' || e.code == 'VALIDATION_ERROR') continue;
          break;
        }
      }
    } finally {
      _uploading = false;
      if (changed) notifyListeners();
    }
  }

  /// Try the upload straight away; keep the photo on the phone if offline.
  Future<String> storePhoto(Uint8List jpeg, String atLoc) async {
    try {
      return await Api.I.uploadPhoto(jpeg, atLoc);
    } catch (_) {
      return toDataUrl(jpeg);
    }
  }
}
