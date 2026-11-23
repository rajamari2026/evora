import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'selection.dart';
import 'store.dart';

class ShareService {
  static const batchSize = 100;

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  static void _busy(BuildContext context, String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the share sheet for a batch, then asks if it was sent.
  /// Returns the ids to mark as sent, or null if not confirmed.
  static Future<List<String>?> _shareAndConfirm(
      BuildContext context, List<AssetEntity> batch, String text) async {
    _busy(context, 'Preparing ${batch.length} photos...');
    final files = <XFile>[];
    final okIds = <String>[];
    for (final a in batch) {
      final f = await a.originFile;
      if (f != null) {
        files.add(XFile(f.path));
        okIds.add(a.id);
      }
    }
    if (!context.mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();

    if (files.isEmpty) {
      _toast(context, 'Could not read these photos.');
      return null;
    }

    await Share.shareXFiles(files, text: text);
    if (!context.mounted) return null;

    final sentOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Did you send these ${files.length} photos?'),
        content: const Text(
            'Mark them as sent so the next batch starts after them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark as sent'),
          ),
        ],
      ),
    );
    return sentOk == true ? okIds : null;
  }

  /// Sends the next 100 photos of an event that have not been sent yet.
  static Future<void> sendNextBatch(
      BuildContext context, AppStore store, DayGroup g) async {
    final remaining = store.remaining(g);
    if (remaining.isEmpty) {
      _toast(context, 'All photos in this event are already sent.');
      return;
    }
    final batch = remaining.take(batchSize).toList();
    final ids = await _shareAndConfirm(context, batch, store.nameOf(g.key) ?? '');
    if (ids == null) return;
    await store.markSentIds(ids);
    if (context.mounted) {
      final left = store.remaining(g).length;
      _toast(context, left == 0 ? 'All photos sent.' : '$left photos left.');
    }
  }

  /// Sends the selected photos (first 100 not yet sent). Sent ones are
  /// deselected, so the rest stay selected for the next batch.
  static Future<void> sendSelected(BuildContext context, AppStore store,
      List<AssetEntity> assets, SelectionController sel) async {
    final unsent = assets.where((a) => !store.isSent(a.id)).toList();
    if (unsent.isEmpty) {
      _toast(context, 'All selected photos were already sent.');
      return;
    }
    final batch = unsent.take(batchSize).toList();
    final ids = await _shareAndConfirm(context, batch, '');
    if (ids == null) return;
    await store.markSentIds(ids);
    sel.removeAll(ids);
    if (context.mounted) {
      final left = unsent.length - ids.length;
      _toast(
          context,
          left <= 0
              ? 'All selected photos sent.'
              : '$left selected photos left. Tap WhatsApp for the next batch.');
    }
  }

  /// Zips every photo of the event into one file and shares it.
  static Future<void> shareZip(
      BuildContext context, AppStore store, DayGroup g) async {
    _busy(context, 'Creating ZIP of ${g.assets.length} photos...');
    try {
      final dir = await getTemporaryDirectory();
      final safe =
          (store.nameOf(g.key) ?? g.key).replaceAll(RegExp(r'[^\w\- ]'), '_');
      final zipPath = '${dir.path}/$safe.zip';
      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();

      final enc = ZipFileEncoder()..create(zipPath);
      for (final a in g.assets) {
        final f = await a.originFile;
        if (f != null) await enc.addFile(f);
      }
      enc.close();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await Share.shareXFiles(
        [XFile(zipPath, mimeType: 'application/zip')],
        text: store.nameOf(g.key) ?? '',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(context, 'ZIP failed: $e');
      }
    }
  }
}
