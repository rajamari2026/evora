import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'e2ee.dart';

class ShareRow {
  final String id;
  final String ownerId;
  final String ownerEmail;
  final String recipientEmail;
  final String title;
  final String status; // uploading, pending, accepted, rejected
  final bool allowDownload;
  final int itemCount;
  final bool encrypted;
  final DateTime createdAt;

  ShareRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        ownerId = j['owner_id'] as String,
        ownerEmail = (j['owner_email'] as String?) ?? '',
        recipientEmail = (j['recipient_email'] as String?) ?? '',
        title = (j['title'] as String?) ?? '',
        status = (j['status'] as String?) ?? 'pending',
        allowDownload = (j['allow_download'] as bool?) ?? false,
        itemCount = (j['item_count'] as num?)?.toInt() ?? 0,
        encrypted = (j['encrypted'] as bool?) ?? false,
        createdAt =
            DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now();
}

/// Thumbnail stored next to a photo: users/share/3.jpg -> users/share/t3.jpg
String thumbPathOf(String path) => path.replaceFirstMapped(
    RegExp(r'/(\d+)\.jpg$'), (m) => '/t${m[1]}.jpg');

/// Talks to Supabase using plain HTTP (no native plugins).
class Backend extends ChangeNotifier {
  String? _access;
  String? _refresh;
  String? email;
  String? userId;
  List<ShareRow> shares = [];
  String? lastError;

  // ---- contacts (enter an email once, then just pick the name) ----------
  Map<String, String> contacts = {};
  final Map<String, List<String>> _pathCache = {};

  Future<void> _loadContacts() async {
    if (userId == null) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('contacts_$userId');
    contacts = raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  String _pretty(String email) {
    final u = email.split('@').first;
    if (u.isEmpty) return email;
    return u[0].toUpperCase() + u.substring(1);
  }

  String nameFor(String email) => contacts[email.toLowerCase()] ?? _pretty(email);

  Future<void> saveContact(String email, String name) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || userId == null) return;
    final n = name.trim();
    contacts[e] = n.isEmpty ? (contacts[e] ?? _pretty(e)) : n;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('contacts_$userId', jsonEncode(contacts));
  }

  /// The other person in a share.
  String counterpart(ShareRow s) =>
      (s.ownerId == userId ? s.recipientEmail : s.ownerEmail).toLowerCase();

  /// People you chat with: saved contacts and anyone you shared with or received from.
  List<String> get chatEmails {
    final latest = <String, DateTime>{};
    for (final s in shares) {
      final e = counterpart(s);
      final t = s.createdAt;
      if (!latest.containsKey(e) || t.isAfter(latest[e]!)) latest[e] = t;
    }
    for (final e in contacts.keys) {
      latest.putIfAbsent(e, () => DateTime.fromMillisecondsSinceEpoch(0));
    }
    final list = latest.keys.toList()
      ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
    return list;
  }

  /// Shares with one person, oldest first.
  List<ShareRow> threadWith(String email) {
    final e = email.toLowerCase();
    final l = shares.where((s) => counterpart(s) == e).toList();
    l.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return l;
  }

  int pendingFrom(String email) => threadWith(email)
      .where((s) => s.ownerId != userId && s.status == 'pending')
      .length;

  /// Photo paths of a share (cached, so chat bubbles do not refetch).
  Future<List<String>> pathsFor(String shareId) async {
    final c = _pathCache[shareId];
    if (c != null) return c;
    final r = await fetchItemPaths(shareId);
    if (r.isNotEmpty) _pathCache[shareId] = r;
    return r;
  }

  void forgetPaths(String shareId) => _pathCache.remove(shareId);

  // ---- end-to-end encryption -------------------------------------------
  List<int>? _myPriv;
  List<int>? _myPub;
  final Map<String, List<int>> _shareKeys = {};
  final Map<String, Uint8List> _plain = {};
  int _plainBytes = 0;

  bool get e2eeReady => _myPriv != null && _myPub != null;

  Future<void> _loadKeys() async {
    _myPriv = null;
    _myPub = null;
    _shareKeys.clear();
    if (userId == null) return;
    final p = await SharedPreferences.getInstance();
    final a = p.getString('e2ee_priv_$userId');
    final b = p.getString('e2ee_pub_$userId');
    if (a != null && b != null) {
      _myPriv = E2ee.unb64(a);
      _myPub = E2ee.unb64(b);
    }
  }

  Future<void> _saveKeys(List<int> priv, List<int> pub) async {
    _myPriv = priv;
    _myPub = pub;
    final p = await SharedPreferences.getInstance();
    await p.setString('e2ee_priv_$userId', E2ee.b64(priv));
    await p.setString('e2ee_pub_$userId', E2ee.b64(pub));
    notifyListeners();
  }

  /// Is there already a passcode-locked key backup on the server?
  Future<bool> serverHasBackup() async {
    final r = await _authed('GET', '/rest/v1/key_backups?select=user_id');
    if (r.statusCode != 200) return false;
    return (jsonDecode(r.body) as List).isNotEmpty;
  }

  /// First time: make keys, lock the private key with the passcode, upload both.
  Future<String?> setupEncryption(String passcode) async {
    try {
      final kp = await E2ee.newKeyPair();
      final w = await E2ee.wrapPrivate(kp.priv, passcode);
      final up = await _authed(
        'POST',
        '/rest/v1/public_keys?on_conflict=user_id',
        json: {'email': email, 'public_key': E2ee.b64(kp.pub)},
        extra: {'Prefer': 'resolution=merge-duplicates'},
      );
      if (up.statusCode >= 300) return _err(up);
      final kb = await _authed(
        'POST',
        '/rest/v1/key_backups?on_conflict=user_id',
        json: {'wrapped_private': w.wrapped, 'salt': w.salt},
        extra: {'Prefer': 'resolution=merge-duplicates'},
      );
      if (kb.statusCode >= 300) return _err(kb);
      await _saveKeys(kp.priv, kp.pub);
      return null;
    } catch (e) {
      return 'Could not turn on encryption: $e';
    }
  }

  /// New phone or after sign-in: open the key backup with the passcode.
  Future<String?> unlockEncryption(String passcode) async {
    try {
      final r =
          await _authed('GET', '/rest/v1/key_backups?select=wrapped_private,salt');
      if (r.statusCode != 200) return _err(r);
      final rows = jsonDecode(r.body) as List;
      if (rows.isEmpty) return 'No encryption key found yet.';
      final row = rows.first as Map;
      List<int> priv;
      try {
        priv = await E2ee.unwrapPrivate(
            passcode, row['salt'] as String, row['wrapped_private'] as String);
      } catch (_) {
        return 'Wrong passcode.';
      }
      final pub = await E2ee.publicFromPrivate(priv);
      await _authed(
        'POST',
        '/rest/v1/public_keys?on_conflict=user_id',
        json: {'email': email, 'public_key': E2ee.b64(pub)},
        extra: {'Prefer': 'resolution=merge-duplicates'},
      );
      await _saveKeys(priv, pub);
      return null;
    } catch (e) {
      return 'Could not unlock: $e';
    }
  }

  Future<List<int>?> publicKeyOf(String address) async {
    final lower = address.toLowerCase();
    // Preferred: ask for one key through a function (does not expose other emails).
    final r = await _authed('POST', '/rest/v1/rpc/public_key_of',
        json: {'p_email': lower});
    if (r.statusCode == 200) {
      final v = jsonDecode(r.body);
      return (v is String && v.isNotEmpty) ? E2ee.unb64(v) : null;
    }
    // Fallback for projects that have not run supabase_hardening.sql yet.
    final q = Uri.encodeQueryComponent(lower);
    final r2 = await _authed(
        'GET', '/rest/v1/public_keys?email=eq.$q&select=public_key');
    if (r2.statusCode != 200) return null;
    final rows = jsonDecode(r2.body) as List;
    if (rows.isEmpty) return null;
    return E2ee.unb64((rows.first as Map)['public_key'] as String);
  }

  /// The photo key of an encrypted share (unlocked with my private key).
  Future<List<int>?> shareKeyFor(ShareRow s) async {
    final cached = _shareKeys[s.id];
    if (cached != null) return cached;
    if (!e2eeReady || email == null) return null;
    final q = Uri.encodeQueryComponent(email!);
    final r = await _authed('GET',
        '/rest/v1/share_keys?share_id=eq.${s.id}&recipient_email=eq.$q&select=eph_public,wrapped_key');
    if (r.statusCode != 200) return null;
    final rows = jsonDecode(r.body) as List;
    if (rows.isEmpty) return null;
    final row = rows.first as Map;
    try {
      final k = await E2ee.unwrapFor(
        myPriv: _myPriv!,
        myPub: _myPub!,
        eph: row['eph_public'] as String,
        wrapped: row['wrapped_key'] as String,
      );
      _shareKeys[s.id] = k;
      return k;
    } catch (_) {
      return null;
    }
  }

  /// Photo bytes ready to show (decrypted on this device if the share is encrypted).
  Future<Uint8List?> plainBytes(ShareRow s, String path) async {
    final ck = '${s.id}|$path';
    final hit = _plain.remove(ck);
    if (hit != null) {
      _plain[ck] = hit;
      return hit;
    }
    final raw = await fetchBytes(path);
    if (raw == null) return null;
    Uint8List out = raw;
    if (s.encrypted) {
      final key = await shareKeyFor(s);
      if (key == null) return null;
      try {
        out = await E2ee.decryptPhoto(raw, key);
      } catch (_) {
        return null;
      }
    }
    _plain[ck] = out;
    _plainBytes += out.length;
    while (_plainBytes > 60 * 1024 * 1024 && _plain.isNotEmpty) {
      final first = _plain.keys.first;
      _plainBytes -= _plain.remove(first)!.length;
    }
    return out;
  }

  bool get ready => Config.ready;
  bool get loggedIn => _access != null && userId != null;

  /// Server-verified admin check. The database function and RLS policies are
  /// the security boundary; the client never grants itself administrator access.
  Future<bool> get isEvoraAdmin async {
    if (!loggedIn) return false;
    try {
      final r = await _authed('POST', '/rest/v1/rpc/is_evora_admin', json: {});
      return r.statusCode == 200 && jsonDecode(r.body) == true;
    } catch (_) {
      return false;
    }
  }

  /// Update-management requests reuse the existing authenticated Supabase
  /// session and refresh-token handling used by photo sharing.
  Future<http.Response> updateRequest(
    String method,
    String path, {
    Object? json,
    Uint8List? bytes,
    Map<String, String>? extra,
  }) => _authed(method, path, json: json, bytes: bytes, extra: extra);

  Map<String, String> get imgHeaders => {
        'apikey': Config.anonKey,
        'Authorization': 'Bearer $_access',
      };

  String imgUrl(String path) =>
      '${Config.url}/storage/v1/object/authenticated/shared/$path';

  List<ShareRow> get incoming =>
      shares.where((s) => s.ownerId != userId).toList();
  List<ShareRow> get requests =>
      incoming.where((s) => s.status == 'pending').toList();
  List<ShareRow> get accepted =>
      incoming.where((s) => s.status == 'accepted').toList();
  List<ShareRow> get mine => shares.where((s) => s.ownerId == userId).toList();

  // ---- session -----------------------------------------------------------

  Future<void> load() async {
    if (!ready) return;
    final p = await SharedPreferences.getInstance();
    _access = p.getString('sb_access');
    _refresh = p.getString('sb_refresh');
    email = p.getString('sb_email');
    userId = p.getString('sb_uid');
    await _loadContacts();
    await _loadKeys();
    notifyListeners();
    if (loggedIn) await refreshShares();
  }

  Future<void> _saveSession() async {
    final p = await SharedPreferences.getInstance();
    if (_access == null) {
      for (final k in ['sb_access', 'sb_refresh', 'sb_email', 'sb_uid']) {
        await p.remove(k);
      }
      return;
    }
    await p.setString('sb_access', _access!);
    await p.setString('sb_refresh', _refresh ?? '');
    await p.setString('sb_email', email ?? '');
    await p.setString('sb_uid', userId ?? '');
  }

  void _setSession(Map<String, dynamic> j) {
    _access = j['access_token'] as String?;
    _refresh = j['refresh_token'] as String?;
    final u = j['user'];
    if (u is Map) {
      userId = u['id'] as String?;
      email = (u['email'] as String?)?.toLowerCase();
    }
    _saveSession();
    Future.wait([_loadContacts(), _loadKeys()]).then((_) => notifyListeners());
    notifyListeners();
  }

  Future<String?> _auth(String path, Map<String, dynamic> body) async {
    try {
      final r = await http.post(
        Uri.parse('${Config.url}/auth/v1/$path'),
        headers: {
          'apikey': Config.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode >= 400) {
        return (j['msg'] ??
                j['error_description'] ??
                j['message'] ??
                'Error ${r.statusCode}')
            .toString();
      }
      if (j['access_token'] == null) {
        return 'Account created. Confirm your email, then sign in.';
      }
      _setSession(j);
      return null;
    } catch (e) {
      return 'Could not connect: $e';
    }
  }

  Future<String?> signIn(String e, String pass) => _auth(
      'token?grant_type=password',
      {'email': e.trim().toLowerCase(), 'password': pass});

  Future<String?> signUp(String e, String pass) =>
      _auth('signup', {'email': e.trim().toLowerCase(), 'password': pass});

  Future<void> signOut() async {
    _access = null;
    _refresh = null;
    email = null;
    userId = null;
    shares = [];
    contacts = {};
    _pathCache.clear();
    _myPriv = null;
    _myPub = null;
    _shareKeys.clear();
    _plain.clear();
    _plainBytes = 0;
    await _saveSession();
    notifyListeners();
  }

  Future<bool> _doRefresh() async {
    if (_refresh == null || _refresh!.isEmpty) return false;
    try {
      final r = await http.post(
        Uri.parse('${Config.url}/auth/v1/token?grant_type=refresh_token'),
        headers: {
          'apikey': Config.anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'refresh_token': _refresh}),
      );
      if (r.statusCode >= 400) {
        await signOut();
        return false;
      }
      _setSession(jsonDecode(r.body) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- low level request -----------------------------------------------

  Future<http.Response> _authed(
    String method,
    String path, {
    Object? json,
    Uint8List? bytes,
    Map<String, String>? extra,
  }) async {
    Future<http.Response> go() async {
      final req = http.Request(method, Uri.parse('${Config.url}$path'));
      req.headers.addAll({
        'apikey': Config.anonKey,
        'Authorization': 'Bearer $_access',
        if (json != null) 'Content-Type': 'application/json',
        ...?extra,
      });
      if (json != null) req.body = jsonEncode(json);
      if (bytes != null) req.bodyBytes = bytes;
      return http.Response.fromStream(await req.send());
    }

    var r = await go();
    if (r.statusCode == 401 && await _doRefresh()) r = await go();
    return r;
  }

  String _err(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map) {
        return (j['message'] ?? j['error'] ?? j['msg'] ?? r.body).toString();
      }
    } catch (_) {}
    return 'Error ${r.statusCode}';
  }

  // ---- shares -----------------------------------------------------------

  Future<void> refreshShares() async {
    if (!loggedIn) return;
    try {
      final r = await _authed(
          'GET', '/rest/v1/shares?select=*&order=created_at.desc');
      if (r.statusCode == 200) {
        shares = (jsonDecode(r.body) as List)
            .map((e) => ShareRow.fromJson(e as Map<String, dynamic>))
            .toList();
        lastError = null;
      } else {
        lastError = _err(r);
      }
    } catch (e) {
      lastError = 'Could not connect: $e';
    }
    notifyListeners();
  }

  /// Uploads the photos (a full version and a small thumbnail each, 3 at a
  /// time) and creates a pending share request. Returns an error or null.
  Future<String?> createShare({
    required String to,
    required String title,
    required bool allowDownload,
    required List<AssetEntity> assets,
    required void Function(int done, int total) onProgress,
    bool encrypt = false,
  }) async {
    final recipient = to.trim().toLowerCase();
    List<int>? recipientPub;
    final photoKey = encrypt ? E2ee.randomBytes(32) : null;
    if (encrypt) {
      if (!e2eeReady) return 'Turn on private sharing first.';
      recipientPub = await publicKeyOf(recipient);
      if (recipientPub == null) {
        return '$recipient has not turned on private sharing yet.';
      }
    }
    final ins = await _authed(
      'POST',
      '/rest/v1/shares',
      json: {
        'owner_email': email,
        'recipient_email': recipient,
        'title': title,
        'allow_download': allowDownload,
        'item_count': assets.length,
        'status': 'uploading',
        'encrypted': encrypt,
      },
      extra: {'Prefer': 'return=representation'},
    );
    if (ins.statusCode >= 300) return _err(ins);
    final shareId = (jsonDecode(ins.body) as List).first['id'] as String;
    final uploaded = <String>[];

    try {
      final total = assets.length;
      // view-only shares get a smaller copy, so the original never leaves the phone
      final fullPx = allowDownload ? 2048 : 1280;
      final fullQ = allowDownload ? 88 : 75;
      final results = List<Map<String, dynamic>?>.filled(total, null);
      var next = 0;
      var done = 0;
      Object? failure;

      Future<void> worker() async {
        while (failure == null) {
          final i = next++;
          if (i >= total) return;
          try {
            final rawFull = await assets[i].thumbnailDataWithSize(
                ThumbnailSize(fullPx, fullPx), quality: fullQ);
            if (rawFull == null) continue;
            final rawSmall = await assets[i].thumbnailDataWithSize(
                const ThumbnailSize(480, 480), quality: 72);
            // end-to-end: encrypt on this phone before anything is uploaded
            final full =
                encrypt ? await E2ee.encryptPhoto(rawFull, photoKey!) : rawFull;
            final small = (rawSmall != null && encrypt)
                ? await E2ee.encryptPhoto(rawSmall, photoKey!)
                : rawSmall;
            final path = '$userId/$shareId/$i.jpg';
            final up = await _authed(
              'POST',
              '/storage/v1/object/shared/$path',
              bytes: full,
              extra: {'Content-Type': 'image/jpeg'},
            );
            if (up.statusCode >= 300) throw _err(up);
            uploaded.add(path);
            if (small != null) {
              final tp = '$userId/$shareId/t$i.jpg';
              final ut = await _authed(
                'POST',
                '/storage/v1/object/shared/$tp',
                bytes: small,
                extra: {'Content-Type': 'image/jpeg'},
              );
              if (ut.statusCode < 300) uploaded.add(tp);
            }
            results[i] = {'share_id': shareId, 'storage_path': path, 'position': i};
            done++;
            onProgress(done, total);
          } catch (e) {
            failure = e;
          }
        }
      }

      await Future.wait([for (var w = 0; w < 3; w++) worker()]);
      if (failure != null) throw failure!;
      final rows = results.whereType<Map<String, dynamic>>().toList();
      if (rows.isEmpty) throw 'No photos could be read';

      final it = await _authed('POST', '/rest/v1/share_items', json: rows);
      if (it.statusCode >= 300) throw _err(it);

      if (encrypt) {
        // lock the photo key for the receiver and for myself (to open on any device)
        final targets = <String, List<int>>{
          recipient: recipientPub!,
          if (email != null) email!.toLowerCase(): _myPub!,
        };
        final keyRows = <Map<String, dynamic>>[];
        for (final t in targets.entries) {
          final w = await E2ee.wrapFor(photoKey!, t.value);
          keyRows.add({
            'share_id': shareId,
            'recipient_email': t.key,
            'eph_public': w.eph,
            'wrapped_key': w.wrapped,
          });
        }
        final kr = await _authed('POST', '/rest/v1/share_keys', json: keyRows);
        if (kr.statusCode >= 300) throw _err(kr);
      }

      final fin = await _authed(
        'PATCH',
        '/rest/v1/shares?id=eq.$shareId',
        json: {'status': 'pending', 'item_count': rows.length},
      );
      if (fin.statusCode >= 300) throw _err(fin);

      if (photoKey != null) _shareKeys[shareId] = photoKey;
      await refreshShares();
      return null;
    } catch (e) {
      if (uploaded.isNotEmpty) {
        await _authed('DELETE', '/storage/v1/object/shared',
            json: {'prefixes': uploaded});
      }
      await _authed('DELETE', '/rest/v1/shares?id=eq.$shareId');
      await refreshShares();
      return e.toString();
    }
  }

  /// Receiver accepts or declines a request.
  Future<String?> respond(String shareId, bool accept) async {
    final r = await _authed('POST', '/rest/v1/rpc/respond_share',
        json: {'p_share_id': shareId, 'p_accept': accept});
    forgetPaths(shareId);
    await refreshShares();
    return r.statusCode >= 300 ? _err(r) : null;
  }

  /// Sender stops sharing: deletes stored photos and the share. Receiver loses access.
  Future<String?> deleteShare(String shareId) async {
    final it = await _authed(
        'GET', '/rest/v1/share_items?share_id=eq.$shareId&select=storage_path');
    if (it.statusCode == 200) {
      final paths = (jsonDecode(it.body) as List)
          .map((e) => (e as Map)['storage_path'] as String)
          .toList();
      if (paths.isNotEmpty) {
        await _authed('DELETE', '/storage/v1/object/shared',
            json: {'prefixes': [...paths, ...paths.map(thumbPathOf)]});
      }
    }
    forgetPaths(shareId);
    final d = await _authed('DELETE', '/rest/v1/shares?id=eq.$shareId');
    await refreshShares();
    return d.statusCode >= 300 ? _err(d) : null;
  }

  Future<List<String>> fetchItemPaths(String shareId) async {
    final r = await _authed('GET',
        '/rest/v1/share_items?share_id=eq.$shareId&select=storage_path&order=position.asc');
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List)
        .map((e) => (e as Map)['storage_path'] as String)
        .toList();
  }

  Future<Uint8List?> fetchBytes(String path) async {
    final r = await _authed(
        'GET', '/storage/v1/object/authenticated/shared/$path');
    return r.statusCode == 200 ? r.bodyBytes : null;
  }
}

final backend = Backend();
