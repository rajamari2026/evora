import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All photos taken on one calendar day.
class DayGroup {
  final String key; // yyyy-MM-dd
  final DateTime date;
  final List<AssetEntity> assets;
  DayGroup(this.key, this.date, this.assets);
}

/// A file the user added on the Files page (copied into the app's own storage).
class AppFile {
  final String name;
  final String path;
  final int size;
  final DateTime added;
  AppFile(this.name, this.path, this.size, this.added);

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'size': size,
        'added': added.millisecondsSinceEpoch,
      };

  factory AppFile.fromJson(Map<String, dynamic> j) => AppFile(
        j['name'] as String,
        j['path'] as String,
        (j['size'] as num).toInt(),
        DateTime.fromMillisecondsSinceEpoch((j['added'] as num).toInt()),
      );
}

class AppStore extends ChangeNotifier {
  late SharedPreferences _prefs;

  /// dayKey -> event name
  Map<String, String> eventNames = {};

  /// dayKey -> path of a cover image copied into the app's own storage
  Map<String, String> covers = {};

  /// custom event key ('c:...') -> name
  Map<String, String> customNames = {};

  /// event key -> ids of photos added to that event by hand
  Map<String, Set<String>> extras = {};

  /// dayKey -> ids of photos already sent via WhatsApp
  Map<String, Set<String>> sent = {};

  List<DayGroup> groups = [];
  List<DayGroup> shotGroups = [];
  List<AppFile> files = [];
  Map<String, AssetEntity> byId = {};
  Map<String, String> dayOf = {};
  bool loading = true;
  bool denied = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    gridColumns.value = (_prefs.getInt('cols') ?? 3).clamp(1, 7).toInt();
    final cv = _prefs.getString('covers');
    if (cv != null) covers = Map<String, String>.from(jsonDecode(cv) as Map);
    final cn = _prefs.getString('customNames');
    if (cn != null) {
      customNames = Map<String, String>.from(jsonDecode(cn) as Map);
    }
    final ex = _prefs.getString('extras');
    if (ex != null) {
      final m = Map<String, dynamic>.from(jsonDecode(ex) as Map);
      extras = m.map((k, v) => MapEntry(k, Set<String>.from(v as List)));
    }
    final fl = _prefs.getString('files');
    if (fl != null) {
      files = (jsonDecode(fl) as List)
          .map((e) => AppFile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final n = _prefs.getString('eventNames');
    if (n != null) {
      eventNames = Map<String, String>.from(jsonDecode(n) as Map);
    }
    final s = _prefs.getString('sent');
    if (s != null) {
      final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
      sent = m.map((k, v) => MapEntry(k, Set<String>.from(v as List)));
    }
    await loadPhotos();
  }

  Future<void> loadPhotos() async {
    loading = true;
    notifyListeners();

    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) {
      denied = true;
      loading = false;
      notifyListeners();
      return;
    }
    denied = false;

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    if (paths.isEmpty) {
      groups = [];
      shotGroups = [];
      loading = false;
      notifyListeners();
      return;
    }

    final all = paths.first;
    final count = await all.assetCountAsync;
    final assets = await all.getAssetListRange(start: 0, end: count);

    final fmt = DateFormat('yyyy-MM-dd');
    final photoMap = <String, DayGroup>{};
    final shotMap = <String, DayGroup>{};
    byId = {};
    dayOf = {};
    for (final a in assets) {
      final d = a.createDateTime;
      final k = fmt.format(d);
      final isShot = (a.relativePath ?? '').toLowerCase().contains('screenshot');
      final map = isShot ? shotMap : photoMap;
      map.putIfAbsent(
          k, () => DayGroup(k, DateTime(d.year, d.month, d.day), []));
      map[k]!.assets.add(a);
      byId[a.id] = a;
      dayOf[a.id] = k;
    }
    groups = photoMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    shotGroups = shotMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    loading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs.setString('eventNames', jsonEncode(eventNames));
    await _prefs.setString('covers', jsonEncode(covers));
    await _prefs.setString('customNames', jsonEncode(customNames));
    await _prefs.setString('files', jsonEncode(files.map((f) => f.toJson()).toList()));
    await _prefs.setString(
      'extras',
      jsonEncode(extras.map((k, v) => MapEntry(k, v.toList()))),
    );
    await _prefs.setString(
      'sent',
      jsonEncode(sent.map((k, v) => MapEntry(k, v.toList()))),
    );
  }

  Future<void> saveColumns() => _prefs.setInt('cols', gridColumns.value);

  String? nameOf(String key) =>
      key.startsWith('c:') ? customNames[key] : eventNames[key];

  /// Cover image path, or null if none (or the file is gone).
  String? coverPath(String key) {
    final p = covers[key];
    if (p == null) return null;
    return File(p).existsSync() ? p : null;
  }

  /// Copies the chosen photo into the app's private storage, so the cover
  /// stays even if the original photo is deleted from the gallery.
  Future<void> setCover(String key, AssetEntity a) async {
    final bytes = await a.thumbnailDataWithSize(
        const ThumbnailSize(900, 900), quality: 88);
    if (bytes == null) return;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/covers');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(
        '${dir.path}/${key.replaceAll(':', '_')}-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    final old = covers[key];
    covers[key] = file.path;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    notifyListeners();
    await _save();
  }

  Future<void> clearCover(String key) async {
    final old = covers.remove(key);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    notifyListeners();
    await _save();
  }

  Future<void> setName(String key, String name) async {
    final t = name.trim();
    if (key.startsWith('c:')) {
      if (t.isNotEmpty) customNames[key] = t;
    } else if (t.isEmpty) {
      eventNames.remove(key);
    } else {
      eventNames[key] = t;
    }
    notifyListeners();
    await _save();
  }

  DayGroup? groupByKey(String key) {
    for (final g in groups) {
      if (g.key == key) return g;
    }
    return null;
  }

  /// All events (named days plus custom events), newest first.
  List<DayGroup> get events {
    final keys = <String>[
      ...eventNames.keys.where((k) => groupByKey(k) != null),
      ...customNames.keys,
    ];
    final out = <DayGroup>[];
    for (final k in keys) {
      final g = eventGroup(k);
      if (g != null) out.add(g);
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// An event with its photos: the day's own photos plus any added by hand.
  DayGroup? eventGroup(String key) {
    final custom = key.startsWith('c:');
    final base = custom ? null : groupByKey(key);
    if (custom && !customNames.containsKey(key)) return null;
    if (!custom && base == null) return null;
    final seen = <String>{};
    final list = <AssetEntity>[];
    if (base != null) {
      for (final a in base.assets) {
        if (seen.add(a.id)) list.add(a);
      }
    }
    for (final id in extras[key] ?? <String>{}) {
      final a = byId[id];
      if (a != null && seen.add(id)) list.add(a);
    }
    list.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    final d = base?.date ??
        (list.isNotEmpty
            ? DateTime(list.first.createDateTime.year,
                list.first.createDateTime.month, list.first.createDateTime.day)
            : DateTime.now());
    return DayGroup(key, d, list);
  }

  /// How many photos of this group were already sent (cheap, used by day headers).
  int sentCountIn(DayGroup g) {
    var n = 0;
    for (final a in g.assets) {
      if (isSent(a.id)) n++;
    }
    return n;
  }

  Set<String> extrasOf(String key) => extras[key] ?? <String>{};

  /// Creates a new event from the given photos. Returns its key.
  Future<String> createEvent(String name, Iterable<String> ids) async {
    final key = 'c:${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    customNames[key] = name.trim().isEmpty ? 'New event' : name.trim();
    extras[key] = ids.toSet();
    notifyListeners();
    await _save();
    return key;
  }

  /// Adds photos to an event. Returns how many were new to it.
  Future<int> addToEvent(String key, Iterable<String> ids) async {
    final own = key.startsWith('c:') ? null : key;
    final set = extras.putIfAbsent(key, () => <String>{});
    final base = own == null ? null : groupByKey(own);
    final inBase = base == null ? <String>{} : base.assets.map((a) => a.id).toSet();
    var n = 0;
    for (final id in ids) {
      if (inBase.contains(id)) continue;
      if (set.add(id)) n++;
    }
    notifyListeners();
    await _save();
    return n;
  }

  /// Removes hand-added photos from an event. Returns how many were removed.
  Future<int> removeFromEvent(String key, Iterable<String> ids) async {
    final set = extras[key];
    if (set == null) return 0;
    var n = 0;
    for (final id in ids) {
      if (set.remove(id)) n++;
    }
    notifyListeners();
    await _save();
    return n;
  }

  /// Deletes the event (name, added photos, cover). Photos stay in the gallery.
  Future<void> deleteEvent(String key) async {
    eventNames.remove(key);
    customNames.remove(key);
    extras.remove(key);
    final old = covers.remove(key);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    notifyListeners();
    await _save();
  }

  /// Ids of this event's photos that were already sent.
  Set<String> sentOf(String key) {
    final g = eventGroup(key);
    if (g == null) return <String>{};
    return g.assets.where((a) => isSent(a.id)).map((a) => a.id).toSet();
  }

  List<AssetEntity> remaining(DayGroup g) =>
      g.assets.where((a) => !isSent(a.id)).toList();

  bool isSent(String id) {
    final k = dayOf[id];
    return k != null && (sent[k]?.contains(id) ?? false);
  }

  Future<void> markSentIds(Iterable<String> ids) async {
    for (final id in ids) {
      final k = dayOf[id];
      if (k != null) sent.putIfAbsent(k, () => <String>{}).add(id);
    }
    notifyListeners();
    await _save();
  }

  /// Selected photos (from Photos or Screenshots), newest first.
  List<AssetEntity> selectedAssets(Set<String> ids) {
    final out = <AssetEntity>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    out.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    return out;
  }

  /// Removes the green "sent" mark from these photos (nothing is deleted).
  Future<void> clearSentIds(Iterable<String> ids) async {
    for (final id in ids) {
      final k = dayOf[id];
      if (k != null) sent[k]?.remove(id);
    }
    notifyListeners();
    await _save();
  }

  Future<void> clearAllSent() async {
    sent.clear();
    notifyListeners();
    await _save();
  }

  /// Copies picked files into the app's storage and lists them. Returns how many.
  Future<int> importFiles(List<String> paths) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/files');
    if (!await dir.exists()) await dir.create(recursive: true);
    var n = 0;
    for (final p in paths) {
      try {
        final src = File(p);
        if (!await src.exists()) continue;
        final name = p.split('/').last;
        final dest =
            File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
        await src.copy(dest.path);
        files.insert(0, AppFile(name, dest.path, await dest.length(), DateTime.now()));
        n++;
      } catch (_) {}
    }
    notifyListeners();
    await _save();
    return n;
  }

  Future<void> removeFile(AppFile f) async {
    files.remove(f);
    try {
      await File(f.path).delete();
    } catch (_) {}
    notifyListeners();
    await _save();
  }

  Future<void> resetSent(String key) async {
    final g = eventGroup(key);
    if (g != null) {
      for (final a in g.assets) {
        final k = dayOf[a.id];
        if (k != null) sent[k]?.remove(a.id);
      }
    }
    notifyListeners();
    await _save();
  }
}

/// One shared store for the whole app (kept simple for version 1).
final store = AppStore();

/// Which bottom tab is open (0 Library, 1 Events, 2 Shared, 3 Updates).
final tabIndex = ValueNotifier<int>(0);

/// Number of photo columns (changed by pinching with two fingers).
final gridColumns = ValueNotifier<int>(3);

/// Library tab: 0 Photos, 1 Screenshots, 2 Files.
final libraryMode = ValueNotifier<int>(0);
