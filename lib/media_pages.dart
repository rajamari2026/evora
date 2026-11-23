import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import 'pages.dart';
import 'selection.dart';
import 'share_service.dart';
import 'shared_pages.dart';
import 'store.dart';
import 'widgets.dart';

/// A small media hub keeps non-camera content out of the main photo timeline.
class MediaHubPage extends StatelessWidget {
  const MediaHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const GlassSliverBar(title: Text('Media')),
          SliverPadding(
            padding: const EdgeInsets.all(18),
            sliver: SliverList.list(children: [
              _MediaCard(
                icon: Icons.screenshot_monitor_rounded,
                title: 'Screenshots',
                subtitle: 'Screenshots grouped by date',
                onTap: () => Navigator.push(
                    context, smoothRoute(const ScreenshotsPage())),
              ),
              const SizedBox(height: 12),
              _MediaCard(
                icon: Icons.folder_rounded,
                title: 'Files',
                subtitle: 'Browse documents and other files on this device',
                onTap: () => Navigator.push(
                    context, smoothRoute(const FilesPage())),
              ),
              const SizedBox(height: 12),
              const _MediaCardInfo(
                icon: Icons.delete_outline_rounded,
                title: 'Recently Deleted',
                subtitle:
                    'Android does not expose a universal trash viewer to third-party gallery apps. Use your device Gallery or Photos app to restore or permanently delete trashed items.',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MediaCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        child: Glass(
          padding: const EdgeInsets.all(18),
          radius: 22,
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      );
}

class _MediaCardInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _MediaCardInfo({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Glass(
        padding: const EdgeInsets.all(18),
        radius: 22,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 5),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
      );
}

class ScreenshotsPage extends StatefulWidget {
  const ScreenshotsPage({super.key});
  @override
  State<ScreenshotsPage> createState() => _ScreenshotsPageState();
}

class _ScreenshotsPageState extends State<ScreenshotsPage> {
  final _selection = SelectionController();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  bool _isScreenshot(AssetEntity a) {
    final value = '${a.title ?? ''} ${a.relativePath ?? ''}'.toLowerCase();
    return value.contains('screenshot') || value.contains('screen_shot') || value.contains('screen-shot');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final assets = store.groups.expand((g) => g.assets).where(_isScreenshot).toList();
          final byDay = <String, List<AssetEntity>>{};
          for (final a in assets) {
            final k = DateFormat('yyyy-MM-dd').format(a.createDateTime);
            byDay.putIfAbsent(k, () => []).add(a);
          }
          final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
          return Scaffold(
            bottomNavigationBar: _selection.active
                ? SelectionBar(
                    sel: _selection,
                    onWhatsApp: () => ShareService.sendSelected(context, store, store.selectedAssets(_selection.selected), _selection),
                    onInApp: () => ShareComposer.open(context, store.selectedAssets(_selection.selected), onDone: _selection.clear),
                  )
                : null,
            body: CustomScrollView(slivers: [
              GlassSliverBar(
                title: const Text('Screenshots'),
                actions: [TextButton(onPressed: _selection.active ? _selection.clear : _selection.start, child: Text(_selection.active ? 'Done' : 'Select'))],
              ),
              if (keys.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No screenshots found')))
              else
                for (final key in keys) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                      child: Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.parse(key)), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    sliver: PhotoGridSliver(group: DayGroup(key, DateTime.parse(key), byDay[key]!), prefix: 'shot-', sel: _selection),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ]),
          );
        },
      );
}

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final List<PlatformFile> _files = [];
  String? _error;

  Future<void> _browse() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any, withData: false);
      if (result == null) return;
      setState(() {
        for (final f in result.files) {
          if (!_files.any((x) => x.path == f.path)) _files.add(f);
        }
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open files: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: _browse, icon: const Icon(Icons.add_rounded), label: const Text('Add files')),
        body: CustomScrollView(slivers: [
          const GlassSliverBar(title: Text('Files')),
          if (_error != null) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(18), child: Text(_error!))),
          if (_files.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Choose documents or other files from your device')))
          else
            SliverList.builder(
              itemCount: _files.length,
              itemBuilder: (context, i) {
                final f = _files[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.insert_drive_file_rounded)),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(f.size)),
                  trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _files.removeAt(i))),
                  onTap: () {
                    final path = f.path;
                    if (path != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected: ${File(path).uri.pathSegments.last}')));
                  },
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
      );

  String _size(int n) => n < 1024 ? '$n B' : n < 1024 * 1024 ? '${(n / 1024).toStringAsFixed(1)} KB' : '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}
