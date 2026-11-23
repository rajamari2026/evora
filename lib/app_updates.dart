import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'backend.dart';
import 'config.dart';

class AppRelease {
  final String id;
  final String versionName;
  final int versionCode;
  final String notes;
  final String apkUrl;
  final bool mandatory;
  final int minSupportedVersionCode;
  final String status;

  const AppRelease({
    required this.id,
    required this.versionName,
    required this.versionCode,
    required this.notes,
    required this.apkUrl,
    required this.mandatory,
    required this.minSupportedVersionCode,
    required this.status,
  });

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        id: (j['id'] ?? '').toString(),
        versionName: (j['version_name'] ?? '').toString(),
        versionCode: (j['version_code'] as num).toInt(),
        notes: (j['release_notes'] ?? '').toString(),
        apkUrl: (j['apk_url'] ?? '').toString(),
        mandatory: j['is_mandatory'] == true,
        minSupportedVersionCode:
            (j['min_supported_version_code'] as num?)?.toInt() ?? 1,
        status: (j['status'] ?? 'prepared').toString(),
      );
}

class AppUpdateService {
  static const _select =
      'id,version_name,version_code,release_notes,apk_url,is_mandatory,min_supported_version_code,status';

  static Future<int> installedVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 1;
  }

  static Future<AppRelease?> latestPublished() async {
    final uri = Uri.parse('${Config.url}/rest/v1/app_releases').replace(
      queryParameters: {
        'select': _select,
        'status': 'eq.published',
        'order': 'version_code.desc',
        'limit': '1',
      },
    );
    final r = await http.get(uri, headers: {'apikey': Config.anonKey});
    if (r.statusCode != 200) {
      throw Exception('Could not check updates (${r.statusCode}).');
    }
    final rows = jsonDecode(r.body) as List;
    if (rows.isEmpty) return null;
    return AppRelease.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  static Future<void> downloadAndInstall(AppRelease release) async {
    final uri = Uri.tryParse(release.apkUrl);
    if (uri == null || uri.scheme != 'https' || uri.host != Uri.parse(Config.url).host) {
      throw Exception('The APK URL is not a trusted Evora download URL.');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('APK download failed (${response.statusCode}).');
      }
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/Evora-${release.versionName}.apk');
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message.isEmpty
            ? 'Android could not open the installer. Allow Evora to install apps in Android settings.'
            : result.message);
      }
    } finally {
      client.close();
    }
  }

  static Future<void> checkAndPrompt(BuildContext context) async {
    try {
      final release = await latestPublished();
      if (release == null || !context.mounted) return;
      final installed = await installedVersionCode();
      if (release.versionCode <= installed) return;
      final mandatory = release.mandatory || installed < release.minSupportedVersionCode;
      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (dialogContext) => AlertDialog(
          title: Text(mandatory ? 'Update required' : 'Evora update available'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Version ${release.versionName} is ready to install.'),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(release.notes),
                ],
              ],
            ),
          ),
          actions: [
            if (!mandatory)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await downloadAndInstall(release);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Update now'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Offline or a temporarily unavailable update service must not block Evora.
    }
  }
}

class AppUpdatesPage extends StatefulWidget {
  const AppUpdatesPage({super.key});

  @override
  State<AppUpdatesPage> createState() => _AppUpdatesPageState();
}

class _AppUpdatesPageState extends State<AppUpdatesPage> {
  AppRelease? _latest;
  List<AppRelease> _adminReleases = [];
  bool _loading = true;
  bool _admin = false;
  bool _busy = false;
  String? _error;
  final _version = TextEditingController();
  final _code = TextEditingController();
  final _notes = TextEditingController();
  bool _mandatory = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _version.dispose();
    _code.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      _latest = await AppUpdateService.latestPublished();
      _admin = await backend.isEvoraAdmin;
      if (_admin) await _loadAdminReleases();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAdminReleases() async {
    final r = await backend.updateRequest(
      'GET',
      '/rest/v1/app_releases?select=${Uri.encodeQueryComponent(AppUpdateService._select)}&order=version_code.desc',
    );
    if (r.statusCode != 200) throw Exception('Could not load release history (${r.statusCode}).');
    _adminReleases = (jsonDecode(r.body) as List)
        .map((e) => AppRelease.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _prepareRelease() async {
    final version = _version.text.trim();
    final code = int.tryParse(_code.text.trim());
    if (version.isEmpty || code == null || code < 1) {
      _toast('Enter a version name and a positive version code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );
      if (picked == null || picked.files.single.path == null) return;
      final file = File(picked.files.single.path!);
      final safeVersion = version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final objectPath = 'releases/$safeVersion/Evora-$safeVersion.apk';
      final bytes = await file.readAsBytes();
      final upload = await backend.updateRequest(
        'POST',
        '/storage/v1/object/evora-apk/$objectPath',
        bytes: bytes,
        extra: {
          'Content-Type': 'application/vnd.android.package-archive',
          'x-upsert': 'true',
        },
      );
      if (upload.statusCode >= 300) {
        throw Exception('APK upload failed (${upload.statusCode}): ${upload.body}');
      }
      final apkUrl = '${Config.url}/storage/v1/object/public/evora-apk/$objectPath';
      final create = await backend.updateRequest(
        'POST',
        '/rest/v1/app_releases',
        json: {
          'version_name': version,
          'version_code': code,
          'release_notes': _notes.text.trim(),
          'apk_url': apkUrl,
          'is_mandatory': _mandatory,
          'min_supported_version_code': _mandatory ? code : 1,
          'status': 'prepared',
          'created_by': backend.userId,
        },
        extra: {'Prefer': 'return=representation'},
      );
      if (create.statusCode >= 300) {
        throw Exception('Could not save release (${create.statusCode}): ${create.body}');
      }
      _version.clear(); _code.clear(); _notes.clear(); _mandatory = false;
      await _refresh();
      _toast('Release prepared. It has NOT been sent to users.');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(AppRelease release, String status) async {
    setState(() => _busy = true);
    try {
      final r = await backend.updateRequest(
        'PATCH',
        '/rest/v1/app_releases?id=eq.${Uri.encodeComponent(release.id)}',
        json: {
          'status': status,
          if (status == 'published') 'published_at': DateTime.now().toUtc().toIso8601String(),
        },
        extra: {'Prefer': 'return=minimal'},
      );
      if (r.statusCode >= 300) throw Exception('Could not update release (${r.statusCode}): ${r.body}');
      await _refresh();
      if (status == 'published') {
        final push = await backend.updateRequest(
          'POST',
          '/functions/v1/notify-release',
          json: {'release_id': release.id},
        );
        if (push.statusCode >= 300) {
          _toast('Release published. In-app update checks are active, but push notification setup is still pending.');
        } else {
          final result = jsonDecode(push.body) as Map<String, dynamic>;
          final sent = (result['sent'] as num?)?.toInt() ?? 0;
          _toast(sent > 0
              ? 'Release published. Push notifications sent to $sent device(s).'
              : 'Release published. No devices are registered for push yet; in-app checks remain active.');
        }
      } else {
        _toast('Release status changed to $status.');
      }
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('Evora Updates')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          sliver: SliverList.list(children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('App version', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) => Text(snap.hasData
                        ? '${snap.data!.version} (build ${snap.data!.buildNumber})'
                        : 'Checking installed version…'),
                  ),
                  const SizedBox(height: 14),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (!_loading && _latest == null) const Text('You are up to date. No published releases found.'),
                  if (_latest != null) ...[
                    Text('Latest published: ${_latest!.versionName}'),
                    if (_latest!.notes.isNotEmpty) Padding(
                      padding: const EdgeInsets.only(top: 6), child: Text(_latest!.notes),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : () async {
                        try { await AppUpdateService.downloadAndInstall(_latest!); }
                        catch (e) { _toast('Update failed: $e'); }
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download and install update'),
                    ),
                  ],
                  TextButton.icon(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh), label: const Text('Check again')),
                ]),
              ),
            ),
            if (_admin) ...[
              const SizedBox(height: 18),
              Text('Administrator · Release management', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Prepare a release', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Upload an APK and save it as prepared. Users will not receive it until you publish it.'),
                    const SizedBox(height: 12),
                    TextField(controller: _version, decoration: const InputDecoration(labelText: 'Version name', hintText: '1.0.1')),
                    TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Android version code', hintText: '2')),
                    TextField(controller: _notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Release notes')),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _mandatory,
                      onChanged: _busy ? null : (v) => setState(() => _mandatory = v),
                      title: const Text('Mark as mandatory update'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _prepareRelease,
                      icon: const Icon(Icons.upload_file),
                      label: Text(_busy ? 'Working…' : 'Upload APK and prepare'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text('Release history', style: Theme.of(context).textTheme.titleMedium),
              if (_adminReleases.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No releases prepared yet.')),
              for (final release in _adminReleases)
                Card(
                  child: ListTile(
                    title: Text('Evora ${release.versionName} · build ${release.versionCode}'),
                    subtitle: Text('${release.status.toUpperCase()}${release.mandatory ? ' · MANDATORY' : ''}\n${release.notes}'),
                    isThreeLine: release.notes.isNotEmpty,
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (v) => _setStatus(release, v),
                      itemBuilder: (_) => [
                        if (release.status != 'published') const PopupMenuItem(value: 'published', child: Text('Publish to all users')),
                        if (release.status == 'published') const PopupMenuItem(value: 'paused', child: Text('Pause release')),
                        if (release.status == 'paused' || release.status == 'prepared') const PopupMenuItem(value: 'published', child: Text('Publish to all users')),
                        const PopupMenuItem(value: 'withdrawn', child: Text('Withdraw release')),
                      ],
                    ),
                  ),
                ),
            ] else if (backend.loggedIn && !_loading) ...[
              const SizedBox(height: 8),
              Text('Signed in as ${backend.email ?? ''}', style: TextStyle(color: dark ? Colors.white70 : Colors.black54)),
            ],
            if (!backend.loggedIn) const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Sign in on the Shared tab to access administrator tools, if your account has been granted admin permission.'),
            ),
          ]),
        ),
      ],
    );
  }
}
