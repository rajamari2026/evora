import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';
import 'widgets.dart';

/// Slivers for the "Files" segment of the Library tab.
/// Files you add are copied into the app, so they stay even if the original is deleted.
List<Widget> filesSlivers(BuildContext context) {
  final t = Theme.of(context).textTheme;
  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => _pick(context),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Add files'),
        ),
      ),
    ),
    if (store.files.isEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Text(
            'Add PDFs, documents or any other files to keep them here and share them.',
            textAlign: TextAlign.center,
            style: t.bodyMedium
                ?.copyWith(color: t.bodyMedium?.color?.withOpacity(0.6)),
          ),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (c, i) => _FileTile(file: store.files[i]),
            childCount: store.files.length,
          ),
        ),
      ),
  ];
}

Future<void> _pick(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null) return;
  final paths = result.files.map((f) => f.path).whereType<String>().toList();
  final n = await store.importFiles(paths);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(n == 0 ? 'No files were added.' : 'Added $n files.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }
}

IconData _iconFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'doc':
    case 'docx':
    case 'txt':
    case 'rtf':
      return Icons.description_rounded;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_rounded;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_rounded;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_rounded;
    case 'mp4':
    case 'mov':
    case 'mkv':
      return Icons.movie_rounded;
    case 'mp3':
    case 'wav':
    case 'm4a':
      return Icons.audiotrack_rounded;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return Icons.image_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _FileTile extends StatelessWidget {
  final AppFile file;
  const _FileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    return PressScale(
      onTap: () {
        HapticFeedback.selectionClick();
        Share.shareXFiles([XFile(file.path)], text: file.name);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.05)]
                : [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.5)],
          ),
          border: Border.all(
              color: Colors.white.withOpacity(dark ? 0.2 : 0.9), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.3 : 0.07),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_iconFor(file.name), color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      '${_size(file.size)}  ${DateFormat('d MMM yyyy').format(file.added)}',
                      style: t.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove from app',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                    title: const Text('Remove this file?'),
                    content: const Text(
                        'It is removed from Evora only. Your original file is not touched.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove')),
                    ],
                  ),
                );
                if (ok == true) await store.removeFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }
}
