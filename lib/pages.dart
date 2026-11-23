import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import 'date_scrollbar.dart';
import 'files_page.dart';
import 'selection.dart';
import 'share_service.dart';
import 'shared_pages.dart';
import 'store.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Rename sheet
// ---------------------------------------------------------------------------

Future<void> showRenameSheet(BuildContext context, String key) async {
  final c = TextEditingController(text: store.nameOf(key) ?? '');
  await showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xF21C1C1E)
        : const Color(0xF2FFFFFF),
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Name this event',
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Pongal family day',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) {
              store.setName(key, v);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                store.setName(key, c.text);
                Navigator.pop(ctx);
              },
              child: const Text('Save event'),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Photo grid (shared by Library and Event pages)
// ---------------------------------------------------------------------------

class PhotoGridSliver extends StatelessWidget {
  final DayGroup group;
  final String prefix;
  final Set<String> sentIds;
  final SelectionController sel;
  const PhotoGridSliver({
    super.key,
    required this.group,
    required this.prefix,
    required this.sel,
    this.sentIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    // Rebuilds when you pinch to change the tile size.
    return ListenableBuilder(
      listenable: gridColumns,
      builder: (context, _) {
        final cols = gridColumns.value;
        final px = cols <= 1 ? 1000 : (cols == 2 ? 600 : (cols <= 4 ? 300 : 220));
        final small = cols >= 5;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: small ? 1 : 2,
            crossAxisSpacing: small ? 1 : 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final a = group.assets[i];
              return MetaData(
                metaData: a.id,
                behavior: HitTestBehavior.translucent,
                child: ListenableBuilder(
                  listenable: sel,
                  builder: (context, _) {
                    final active = sel.active;
                    final picked = sel.isSelected(a.id);
                    final isSent = store.isSent(a.id);
                    return GestureDetector(
                      onTap: () {
                        if (active) {
                          sel.toggle(a.id);
                        } else {
                          Navigator.push(
                            context,
                            smoothRoute(ViewerPage(
                                assets: group.assets,
                                index: i,
                                prefix: prefix)),
                          );
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            margin: EdgeInsets.all(picked ? (small ? 4 : 9) : 0),
                            clipBehavior: picked ? Clip.antiAlias : Clip.none,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(picked ? 10 : 0),
                            ),
                            child: Hero(
                              tag: '$prefix${a.id}',
                              child: PhotoThumb(asset: a, size: px),
                            ),
                          ),
                          if (isSent && !picked)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF30D158)
                                        .withOpacity(0.18),
                                    border: Border.all(
                                      color: const Color(0xFF30D158),
                                      width: small ? 1.5 : 2.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (isSent)
                            Positioned(
                              left: 5,
                              top: 5,
                              child: _SentBadge(compact: small),
                            ),
                          if (active)
                            Positioned(
                              right: small ? 4 : 8,
                              bottom: small ? 4 : 8,
                              child: _SelectCircle(
                                  on: picked, size: small ? 18 : 24),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
            childCount: group.assets.length,
          ),
        );
      },
    );
  }
}

class _SelectCircle extends StatelessWidget {
  final bool on;
  final double size;
  const _SelectCircle({required this.on, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withOpacity(0.25),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Icon(Icons.check_rounded, size: size * 0.62, color: Colors.white),
      ),
    );
  }
}

class _SentBadge extends StatelessWidget {
  final bool compact;
  final String label;
  const _SentBadge({this.compact = false, this.label = 'Sent'});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF30D158);
    if (compact) {
      return const Icon(Icons.check_circle_rounded, color: green, size: 16);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

class LibraryPage extends StatefulWidget {
  final SelectionController sel;
  const LibraryPage({super.key, required this.sel});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.sel;
    return ListenableBuilder(
      listenable: Listenable.merge([store, libraryMode]),
      builder: (context, _) {
        final mode = libraryMode.value;
        final groups = mode == 1 ? store.shotGroups : store.groups;
        final loaded = !store.loading && !store.denied;
        final hasPhotos = loaded && mode != 2 && groups.isNotEmpty;

        final slivers = <Widget>[
          ListenableBuilder(
            listenable: sel,
            builder: (context, _) => GlassSliverBar(
              title: Text(sel.active
                  ? (sel.count == 0 ? 'Select Items' : '${sel.count} Selected')
                  : 'Library'),
              actions: [
                if (hasPhotos)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton(
                      onPressed: sel.active ? sel.clear : sel.start,
                      child: Text(sel.active ? 'Done' : 'Select',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (!sel.active && mode != 2)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    onSelected: (v) {
                      if (v == 'clear') confirmClearSent(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'clear', child: Text('Clear all sent marks')),
                    ],
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: mode,
                onValueChanged: (v) {
                  if (v == null || v == mode) return;
                  HapticFeedback.selectionClick();
                  sel.clear();
                  libraryMode.value = v;
                  if (scroll.hasClients) scroll.jumpTo(0);
                },
                children: const {
                  0: _Seg('Photos'),
                  1: _Seg('Screenshots'),
                  2: _Seg('Files'),
                },
              ),
            ),
          ),
        ];

        if (mode == 2) {
          slivers.addAll(filesSlivers(context));
        } else if (store.loading) {
          slivers.add(const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ));
        } else if (store.denied) {
          slivers.add(SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: Icons.lock_outline_rounded,
              title: 'Allow photo access',
              body:
                  'Evora needs access to your photos to group them by date.',
              action: 'Open settings',
              onAction: PhotoManager.openSetting,
            ),
          ));
        } else if (groups.isEmpty) {
          slivers.add(SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: Icons.photo_outlined,
              title: mode == 1 ? 'No screenshots' : 'No photos yet',
              body: mode == 1
                  ? 'Your screenshots appear here, separate from your photos.'
                  : 'Photos you take will appear here, grouped by day.',
            ),
          ));
        } else {
          for (final g in groups) {
            slivers.add(SliverMainAxisGroup(slivers: [
              SliverToBoxAdapter(
                child: _DayHeader(group: g, sel: sel, events: mode == 0),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: PhotoGridSliver(group: g, prefix: 'lib-', sel: sel),
              ),
            ]));
          }
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));

        return Stack(
          children: [
            Positioned.fill(
              child: SelectionScope(
                ctrl: sel,
                scroll: scroll,
                child: CustomScrollView(controller: scroll, slivers: slivers),
              ),
            ),
            if (hasPhotos) DateScrollbar(scroll: scroll, groups: groups),
          ],
        );
      },
    );
  }
}

class _Seg extends StatelessWidget {
  final String label;
  const _Seg(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(label),
      );
}

Future<void> confirmClearSent(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Clear all sent marks?'),
      content: const Text(
          'Your photos are not deleted. Only the green "Sent" marks are removed.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear')),
      ],
    ),
  );
  if (ok == true) await store.clearAllSent();
}

void _snack(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}

/// Moves the selected photos to Android's own trash (Recently Deleted).
/// Android asks you to confirm. Photos can be restored from your Gallery or
/// Google Photos trash for about 30 days. Needs Android 11 or newer.
Future<void> deleteSelected(
  BuildContext context,
  List<AssetEntity> assets,
  SelectionController sel,
) async {
  if (assets.isEmpty) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Move ${assets.length} photos to Recently Deleted?'),
      content: const Text(
          'They go to your phone\'s trash, where you can restore them for about 30 days. Android will ask you to confirm.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF453A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to trash')),
      ],
    ),
  );
  if (ok != true) return;

  final before = store.byId.length;
  var supported = true;
  try {
    final dynamic editor = PhotoManager.editor;
    await editor.android.moveToTrash(assets);
  } catch (_) {
    supported = false;
  }
  if (!supported) {
    _snack(context,
        'Recently Deleted needs Android 11 or newer. Delete from your gallery app instead.');
    return;
  }
  sel.clear();
  await store.loadPhotos();
  final removed = before - store.byId.length;
  _snack(
      context,
      removed > 0
          ? 'Moved $removed photos to Recently Deleted.'
          : 'No photos were moved.');
}

class _DayHeader extends StatelessWidget {
  final DayGroup group;
  final SelectionController sel;
  final bool events;
  const _DayHeader(
      {required this.group, required this.sel, this.events = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = events ? store.nameOf(group.key) : null;
    final date = DateFormat('EEEE, d MMMM yyyy').format(group.date);
    final accent = Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: sel,
      builder: (context, _) {
        final ids = group.assets.map((a) => a.id);
        final allOn = sel.active && ids.every(sel.isSelected);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: name != null
                    ? PressScale(
                        onTap: () {
                          if (sel.active) return;
                          Navigator.push(context,
                              smoothRoute(EventPage(groupKey: group.key)));
                        },
                        onLongPress: () => showRenameSheet(context, group.key),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: t.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(date,
                                style: t.bodySmall?.copyWith(
                                    color:
                                        t.bodySmall?.color?.withOpacity(0.7))),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(date,
                              style: t.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (!sel.active && events) ...[
                            const SizedBox(height: 6),
                            PressScale(
                              onTap: () => showRenameSheet(context, group.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_rounded,
                                        size: 14, color: accent),
                                    const SizedBox(width: 5),
                                    Text('Name this event',
                                        style: t.labelMedium?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              if (sel.active)
                TextButton(
                  onPressed: () =>
                      allOn ? sel.removeAll(ids) : sel.addAll(ids),
                  child: Text(allOn ? 'Deselect' : 'Select all',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (store.sentCountIn(group) > 0) ...[
                        _SentBadge(label: '${store.sentCountIn(group)} sent'),
                        const SizedBox(width: 8),
                      ],
                      Text('${group.assets.length}',
                          style: t.bodyMedium?.copyWith(
                              color: t.bodyMedium?.color?.withOpacity(0.6),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final events = store.events;
        return CustomScrollView(
          slivers: [
            const GlassSliverBar(title: Text('Events')),
            if (events.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: Icons.photo_album_outlined,
                  title: 'No events yet',
                  body:
                      'Open Library and tap "Name this event" on any day to create one.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (c, i) => _EventCard(group: events[i]),
                    childCount: events.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  final DayGroup group;
  const _EventCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sentCount = store.sentOf(group.key).length;
    final sub =
        '${DateFormat('d MMM yyyy').format(group.date)}  ${group.assets.length} photos';

    return PressScale(
      onTap: () => Navigator.push(
          context, smoothRoute(EventPage(groupKey: group.key))),
      onLongPress: () => showRenameSheet(context, group.key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox.expand(
                child: _eventThumb(group, 500),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(store.nameOf(group.key) ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall
                  ?.copyWith(color: t.bodySmall?.color?.withOpacity(0.65))),
          if (sentCount > 0)
            Text('$sentCount sent',
                style: t.bodySmall?.copyWith(
                    color: const Color(0xFF30D158),
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event detail + WhatsApp batch sharing
// ---------------------------------------------------------------------------

class EventPage extends StatefulWidget {
  final String groupKey;
  const EventPage({super.key, required this.groupKey});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final sel = SelectionController();
  final scroll = ScrollController();

  @override
  void dispose() {
    sel.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.eventGroup(widget.groupKey);
        if (g == null) return const Scaffold();

        final t = Theme.of(context).textTheme;
        final total = g.assets.length;
        final sentIds = store.sentOf(g.key);
        final remaining = store.remaining(g).length;
        final sentCount = total - remaining;
        final next = math.min(ShareService.batchSize, remaining);
        final batches = (total / ShareService.batchSize).ceil();
        final batchNo = remaining == 0
            ? batches
            : (sentCount / ShareService.batchSize).floor() + 1;

        return Scaffold(
          extendBody: true,
          body: SelectionScope(
            ctrl: sel,
            scroll: scroll,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                ListenableBuilder(
                  listenable: sel,
                  builder: (context, _) => GlassSliverBar(
                    title: Text(sel.active
                        ? (sel.count == 0
                            ? 'Select Items'
                            : '${sel.count} Selected')
                        : (store.nameOf(g.key) ?? '')),
                    actions: [
                      TextButton(
                        onPressed: sel.active ? sel.clear : sel.start,
                        child: Text(sel.active ? 'Done' : 'Select',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (!sel.active)
                        PopupMenuButton<String>(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          onSelected: (v) async {
                            if (v == 'rename') showRenameSheet(context, g.key);
                            if (v == 'reset') store.resetSent(g.key);
                            if (v == 'cover') showCoverPicker(context, g);
                            if (v == 'nocover') store.clearCover(g.key);
                            if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22)),
                                  title: const Text('Delete this event?'),
                                  content: const Text(
                                      'Your photos stay in the gallery. Only the event is removed.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await store.deleteEvent(g.key);
                                if (context.mounted) Navigator.pop(context);
                              }
                            }
                            if (v == 'all') {
                              sel.start();
                              sel.addAll(g.assets.map((a) => a.id));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'all', child: Text('Select all')),
                            PopupMenuItem(
                                value: 'rename', child: Text('Rename event')),
                            PopupMenuItem(
                                value: 'cover',
                                child: Text('Set cover photo')),
                            PopupMenuItem(
                                value: 'nocover',
                                child: Text('Remove cover photo')),
                            PopupMenuItem(
                                value: 'reset',
                                child: Text('Reset sent photos')),
                            PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete event')),
                          ],
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('EEEE, d MMMM yyyy').format(g.date)}  $total photos',
                          style: t.bodyMedium?.copyWith(
                              color: t.bodyMedium?.color?.withOpacity(0.7)),
                        ),
                        const SizedBox(height: 12),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: total == 0 ? 0 : sentCount / total),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              color: const Color(0xFF30D158),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          remaining == 0
                              ? 'All $total photos sent'
                              : '$sentCount sent, $remaining left. Batch $batchNo of $batches.',
                          style:
                              t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  sliver: PhotoGridSliver(
                      group: g, prefix: 'evt-', sel: sel, sentIds: sentIds),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: sel,
            builder: (context, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: sel.active
                  ? SelectionBar(
                      key: const ValueKey('sel'),
                      sel: sel,
                      onWhatsApp: () => ShareService.sendSelected(
                          context, store, store.selectedAssets(sel.selected), sel),
                      onInApp: () => ShareComposer.open(
                          context, store.selectedAssets(sel.selected),
                          onDone: sel.clear),
                      onAddToEvent: () => showAddToEventSheet(
                          context, sel.selected.toList(),
                          exclude: g.key, onDone: sel.clear),
                      onMarkSent: () {
                        store.markSentIds(sel.selected);
                        sel.clear();
                      },
                      onClearSent: () {
                        store.clearSentIds(sel.selected);
                        sel.clear();
                      },
                      onDelete: () => deleteSelected(
                          context, store.selectedAssets(sel.selected), sel),
                      onRemove: (g.key.startsWith('c:') ||
                              store.extrasOf(g.key).isNotEmpty)
                          ? () async {
                              final n = await store.removeFromEvent(
                                  g.key, sel.selected);
                              sel.clear();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(n == 0
                                      ? "Photos from this event's own date can't be removed."
                                      : 'Removed $n photos from the event.'),
                                  behavior: SnackBarBehavior.floating,
                                ));
                              }
                            }
                          : null,
                    )
                  : GlassBar(
                      key: const ValueKey('bar'),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: remaining == 0
                                  ? null
                                  : () {
                                      HapticFeedback.mediumImpact();
                                      ShareService.sendNextBatch(
                                          context, store, g);
                                    },
                              icon: const Icon(Icons.send_rounded, size: 20),
                              label: Text(remaining == 0
                                  ? 'All sent'
                                  : 'Send next $next via WhatsApp'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: 'Share all as ZIP',
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(15),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              ShareService.shareZip(context, store, g);
                            },
                            icon: const Icon(Icons.folder_zip_rounded),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen photo viewer (pinch, double-tap and pan to zoom)
// ---------------------------------------------------------------------------

class ViewerPage extends StatefulWidget {
  final List<AssetEntity> assets;
  final int index;
  final String prefix;
  const ViewerPage({
    super.key,
    required this.assets,
    required this.index,
    required this.prefix,
  });

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final PageController pc = PageController(initialPage: widget.index);
  late int cur = widget.index;
  bool chrome = true;
  bool zoomed = false;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assets[cur];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: pc,
            // swiping to the next photo is paused while zoomed in
            physics: zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.assets.length,
            onPageChanged: (i) => setState(() {
              cur = i;
              zoomed = false;
            }),
            itemBuilder: (_, i) => _FullImage(
              asset: widget.assets[i],
              tag: '${widget.prefix}${widget.assets[i].id}',
              onTap: () => setState(() => chrome = !chrome),
              onZoom: (z) {
                if (i == cur && z != zoomed) setState(() => zoomed = z);
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !chrome,
              child: AnimatedOpacity(
                opacity: chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      8, MediaQuery.of(context).padding.top + 4, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      GlassCircleButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('d MMM yyyy, h:mm a')
                            .format(a.createDateTime),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullImage extends StatefulWidget {
  final AssetEntity asset;
  final String tag;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;
  const _FullImage({
    required this.asset,
    required this.tag,
    required this.onTap,
    required this.onZoom,
  });

  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  Uint8List? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // quick small preview first, then a sharp version for zooming
  Future<void> _load() async {
    final small =
        await widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(600));
    if (mounted && data == null && small != null) setState(() => data = small);
    final big = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize(2400, 2400), quality: 92);
    if (mounted && big != null) setState(() => data = big);
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      );
    }
    return ZoomableImage(
      onTap: widget.onTap,
      onZoomChanged: widget.onZoom,
      child: Center(
        child: Hero(
          tag: widget.tag,
          child: Image.memory(data!, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cover picker
// ---------------------------------------------------------------------------

Future<void> showCoverPicker(BuildContext context, DayGroup g) async {
  final dark = Theme.of(context).brightness == Brightness.dark;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor:
        dark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose cover photo',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'A copy is saved inside the app, so it stays even if you delete the original photo.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: g.assets.length,
              itemBuilder: (c, i) => GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  await store.setCover(g.key, g.assets[i]);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Cover saved.'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ));
                  }
                },
                child: PhotoThumb(asset: g.assets[i]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Event thumbnail + "Add to event" sheet
// ---------------------------------------------------------------------------

Widget _eventThumb(DayGroup g, int size) {
  final cover = store.coverPath(g.key);
  if (cover != null) {
    return Image.file(File(cover), fit: BoxFit.cover, gaplessPlayback: true);
  }
  if (g.assets.isEmpty) {
    return const ColoredBox(
      color: Color(0x22888888),
      child: Center(child: Icon(Icons.photo_album_outlined, size: 30)),
    );
  }
  return PhotoThumb(asset: g.assets.first, size: size);
}

/// Group the given photos into a new event, or add them to an existing one.
Future<void> showAddToEventSheet(
  BuildContext context,
  List<String> ids, {
  String? exclude,
  VoidCallback? onDone,
}) async {
  if (ids.isEmpty) return;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final nameCtl = TextEditingController();

  void toast(String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: dark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final events = store.events.where((e) => e.key != exclude).toList();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add ${ids.length} photos to an event',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'New event name',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        final name = nameCtl.text.trim();
                        if (name.isEmpty) return;
                        HapticFeedback.mediumImpact();
                        Navigator.pop(ctx);
                        await store.createEvent(name, ids);
                        toast('Event "$name" created with ${ids.length} photos.');
                        onDone?.call();
                      },
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: events.isEmpty
                    ? const Center(
                        child: Text('No other events yet. Create one above.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: events.length,
                        itemBuilder: (c, i) {
                          final e = events[i];
                          final name = store.nameOf(e.key) ?? '';
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                  width: 52, height: 52, child: _eventThumb(e, 150)),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text('${e.assets.length} photos'),
                            onTap: () async {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(ctx);
                              final n = await store.addToEvent(e.key, ids);
                              toast(n == 0
                                  ? 'Those photos are already in "$name".'
                                  : 'Added $n photos to "$name".');
                              onDone?.call();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
