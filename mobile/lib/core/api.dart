import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Default server. Override at build time with
/// `--dart-define=API_BASE=https://your-site.vercel.app`, or from the
/// "Server" link on the sign-in screen.
const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://bookends-cleaning.vercel.app',
);

class ApiException implements Exception {
  final int status;
  final String message;
  final String code;
  final Map<String, dynamic> body;
  ApiException(this.status, this.message, this.code, [this.body = const {}]);
  bool get isOffline => status == 0;
  @override
  String toString() => message;
}

/// Talks to the Express API.
///
/// The website keeps the refresh token in an httpOnly cookie. A phone app has
/// no cookie jar, so the token is read from the Set-Cookie header on sign-in
/// and kept in the platform keystore; /api/auth/refresh accepts it in the
/// body (tokenService.readRefreshCookie).
class Api {
  Api._();
  static final Api I = Api._();

  static const _kRefresh = 'bk_refresh_token';
  static const _kBase = 'bk_api_base';
  static const _cookieName = 'bk_refresh';

  final _secure = const FlutterSecureStorage();
  final _client = http.Client();

  String base = kDefaultApiBase;
  String? accessToken;
  DateTime? _accessExpires;
  Future<bool>? _refreshing;

  /// Called when the session is gone for good (refresh refused).
  void Function()? onSignedOut;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString(_kBase) ?? kDefaultApiBase;
  }

  Future<void> setBase(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('http')) u = 'https://$u';
    base = u;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, u);
  }

  Future<String?> get refreshToken => _secure.read(key: _kRefresh);

  Future<void> _keepRefresh(http.BaseResponse r) async {
    final raw = r.headers['set-cookie'];
    if (raw == null) return;
    // Several cookies may be folded into one header separated by commas.
    final m = RegExp('(?:^|[,;\\s])${RegExp.escape(_cookieName)}=([^;,]*)').firstMatch(raw);
    if (m == null) return;
    final v = Uri.decodeComponent(m.group(1) ?? '');
    if (v.isEmpty) {
      await _secure.delete(key: _kRefresh);
    } else {
      await _secure.write(key: _kRefresh, value: v);
    }
  }

  void _takeSession(Map<String, dynamic> j) {
    accessToken = j['accessToken'] as String?;
    final secs = (j['expiresIn'] as num?)?.toInt() ?? 900;
    _accessExpires = DateTime.now().add(Duration(seconds: secs));
  }

  Future<void> clearSession() async {
    accessToken = null;
    _accessExpires = null;
    await _secure.delete(key: _kRefresh);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$base$path');
    return query == null ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.body.isEmpty) return {};
    try {
      final d = jsonDecode(r.body);
      return d is Map<String, dynamic> ? d : {'data': d};
    } catch (_) {
      return {'error': 'Unexpected reply from the server (${r.statusCode})'};
    }
  }

  ApiException _error(http.Response r, Map<String, dynamic> j) => ApiException(
        r.statusCode,
        (j['error'] as String?) ?? 'Something went wrong (${r.statusCode})',
        (j['code'] as String?) ?? 'ERROR',
        j,
      );

  /// POST /api/auth/refresh. Several callers may ask at once; one request.
  Future<bool> refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Map<String, dynamic>? lastSession;

  Future<bool> _doRefresh() async {
    final rt = await refreshToken;
    if (rt == null) return false;
    http.Response r;
    try {
      r = await _client
          .post(_uri('/api/auth/refresh'),
              headers: {
                'Content-Type': 'application/json',
                'Cookie': '$_cookieName=${Uri.encodeComponent(rt)}',
              },
              body: jsonEncode({'refreshToken': rt}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException(0, 'No internet connection', 'OFFLINE');
    }
    final j = _decode(r);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      await _keepRefresh(r);
      _takeSession(j);
      lastSession = j;
      return true;
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      await clearSession();
      return false;
    }
    throw _error(r, j);
  }

  Future<void> _ensureFresh() async {
    if (accessToken == null) {
      await refresh();
      return;
    }
    final exp = _accessExpires;
    if (exp != null && DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)))) {
      await refresh();
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
    bool retried = false,
  }) async {
    if (auth) await _ensureFresh();
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth && accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    // Auth routes still read the cookie first; send it so logout works.
    if (path.startsWith('/api/auth/')) {
      final rt = await refreshToken;
      if (rt != null) headers['Cookie'] = '$_cookieName=${Uri.encodeComponent(rt)}';
    }
    final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);

    http.Response r;
    try {
      r = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw ApiException(0, 'The server is taking too long. Check your connection.', 'OFFLINE');
    } catch (_) {
      throw ApiException(0, 'No internet connection', 'OFFLINE');
    }
    final j = _decode(r);
    if (r.statusCode == 401 && auth && !retried) {
      if (await refresh()) {
        return request(method, path, body: body, query: query, auth: auth, retried: true);
      }
      onSignedOut?.call();
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw _error(r, j);
    if (path == '/api/auth/login' || path == '/api/auth/change-password') {
      await _keepRefresh(r);
      _takeSession(j);
    }
    return j;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, bool auth = true}) =>
      request('GET', path, query: query, auth: auth);
  Future<Map<String, dynamic>> post(String path, [Object? body, bool auth = true]) =>
      request('POST', path, body: body ?? {}, auth: auth);
  Future<Map<String, dynamic>> patch(String path, Object body) => request('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path, {Map<String, String>? query}) =>
      request('DELETE', path, query: query);

  /// POST /api/photos with raw JPEG bytes. Returns the stored URL.
  Future<String> uploadPhoto(Uint8List jpeg, String loc) async {
    await _ensureFresh();
    http.Response r;
    try {
      r = await _client
          .post(_uri('/api/photos', {'loc': loc}),
              headers: {
                'Content-Type': 'image/jpeg',
                if (accessToken != null) 'Authorization': 'Bearer $accessToken',
              },
              body: jpeg)
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw ApiException(0, 'No internet connection', 'OFFLINE');
    }
    final j = _decode(r);
    if (r.statusCode < 200 || r.statusCode >= 300) throw _error(r, j);
    return j['url'] as String;
  }

  Future<void> logout() async {
    try {
      await request('POST', '/api/auth/logout', body: {'refreshToken': await refreshToken}, auth: false);
    } catch (_) {}
    await clearSession();
  }
}
