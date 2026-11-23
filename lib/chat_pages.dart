import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import 'backend.dart';
import 'date_scrollbar.dart';
import 'pages.dart' show PhotoGridSliver;
import 'selection.dart';
import 'shared_pages.dart';
import 'store.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

const _avatarColors = <List<Color>>[
  [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
  [Color(0xFFFF9F0A), Color(0xFFFF453A)],
  [Color(0xFF30D158), Color(0xFF0A84FF)],
  [Color(0xFFBF5AF2), Color(0xFFFF375F)],
  [Color(0xFF64D2FF), Color(0xFF30D158)],
];

class ChatAvatar extends StatelessWidget {
  final String name;
  final double size;
  const ChatAvatar({super.key, required this.name, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final c = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c,
        ),
      ),
      child: Text(letter,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.44)),
    );
  }
}

bool _isEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

// ---------------------------------------------------------------------------
// Chat list (the Shared tab)
// ---------------------------------------------------------------------------

class ChatList extends StatelessWidget {
  const ChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final emails = backend.chatEmails;
        return RefreshIndicator(
          onRefresh: backend.refreshShares,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              GlassSliverBar(
                title: const Text('Shared'),
                actions: [
                  IconButton(
                    tooltip: 'New chat',
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    onPressed: () => showNewChatSheet(context),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.account_circle_outlined),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    onSelected: (v) {
                      if (v == 'out') backend.signOut();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          enabled: false, child: Text(backend.email ?? '')),
                      const PopupMenuItem(value: 'out', child: Text('Sign out')),
                    ],
                  ),
                ],
              ),
              if (backend.lastError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(backend.lastError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ),
              if (!backend.e2eeReady)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: PressScale(
                      onTap: () => showE2eeSetup(context),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_rounded,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Turn on private sharing',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'End-to-end encryption: only you and the receiver can open your photos.',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (emails.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_rounded,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text('Share photos like a chat',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text(
                          'Add a person once with their email. After that, just pick their name and send photos.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => showNewChatSheet(context),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('New chat'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (c, i) => _ChatRow(email: emails[i]),
                      childCount: emails.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
        );
      },
    );
  }
}

class _ChatRow extends StatelessWidget {
  final String email;
  const _ChatRow({required this.email});

  String _preview(List<ShareRow> thread) {
    if (thread.isEmpty) return 'Tap to send photos';
    final s = thread.last;
    final mine = s.ownerId == backend.userId;
    if (mine) {
      if (s.status == 'pending') return 'Waiting for them to accept';
      if (s.status == 'rejected') return 'Declined your photos';
      return 'You sent ${s.itemCount} photos';
    }
    if (s.status == 'pending') return 'Sent you ${s.itemCount} photos';
    return 'You received ${s.itemCount} photos';
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('h:mm a').format(t);
    }
    return DateFormat('d MMM').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = backend.nameFor(email);
    final thread = backend.threadWith(email);
    final pending = backend.pendingFrom(email);
    return PressScale(
      onTap: () =>
          Navigator.push(context, smoothRoute(ChatPage(email: email))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            ChatAvatar(name: name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_preview(thread),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                          color: t.bodyMedium?.color?.withOpacity(0.65),
                          fontWeight:
                              pending > 0 ? FontWeight.w700 : FontWeight.w400)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (thread.isNotEmpty)
                  Text(_when(thread.last.createdAt), style: t.bodySmall),
                if (pending > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF453A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$pending',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New chat sheet (enter an email once)
// ---------------------------------------------------------------------------

Future<void> showNewChatSheet(BuildContext context) async {
  final emailCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final dark = Theme.of(context).brightness == Brightness.dark;
  String? error;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: dark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New chat',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('You only enter the email once. Next time just pick the name.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: emailCtl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Their email',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Name (optional)',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final e = emailCtl.text.trim().toLowerCase();
                  if (!_isEmail(e)) {
                    setSheet(() => error = 'Enter a valid email address.');
                    return;
                  }
                  if (e == backend.email) {
                    setSheet(() => error = 'That is your own email.');
                    return;
                  }
                  HapticFeedback.mediumImpact();
                  await backend.saveContact(e, nameCtl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    Navigator.push(context, smoothRoute(ChatPage(email: e)));
                  }
                },
                child: const Text('Start chat'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Chat page: a conversation made of photo shares
// ---------------------------------------------------------------------------

class ChatPage extends StatefulWidget {
  final String email;
  const ChatPage({super.key, required this.email});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    backend.refreshShares();
  }

  Future<void> _addPhotos() async {
    final name = backend.nameFor(widget.email);
    final picked = await Navigator.push<List<AssetEntity>>(
      context,
      smoothRoute<List<AssetEntity>>(PhotoPickerPage(title: 'Send to $name')),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await ShareComposer.sendTo(context, widget.email, picked);
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: backend.nameFor(widget.email));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Contact name'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await backend.saveContact(widget.email, c.text);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final thread = backend.threadWith(widget.email);
        final name = backend.nameFor(widget.email);
        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              const Positioned.fill(child: AmbientBackground()),
              Positioned.fill(
                child: thread.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No photos yet.\nTap "Add photos" to send the first ones to $name.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true, // newest at the bottom, like a chat
                        padding: EdgeInsets.fromLTRB(
                            12, mq.padding.top + 76, 12, mq.padding.bottom + 110),
                        itemCount: thread.length,
                        itemBuilder: (c, i) =>
                            ShareBubble(share: thread[thread.length - 1 - i]),
                      ),
              ),
              Positioned(
                top: mq.padding.top + 6,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    GlassCircleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.maybePop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Glass(
                        radius: 23,
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: SizedBox(
                          height: 46,
                          child: Row(
                            children: [
                              ChatAvatar(name: name, size: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    Text(widget.email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Rename',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: _rename,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: GlassBar(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _addPhotos,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Add photos'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// One share shown as a chat bubble
// ---------------------------------------------------------------------------

class ShareBubble extends StatefulWidget {
  final ShareRow share;
  const ShareBubble({super.key, required this.share});

  @override
  State<ShareBubble> createState() => _ShareBubbleState();
}

class _ShareBubbleState extends State<ShareBubble> {
  bool busy = false;

  ShareRow get s => widget.share;
  bool get mine => s.ownerId == backend.userId;
  bool get locked => !mine && s.status != 'accepted';

  Future<void> _answer(bool accept) async {
    HapticFeedback.mediumImpact();
    setState(() => busy = true);
    final err = await backend.respond(s.id, accept);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _stop() async {
    if (!mine) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Stop sharing?'),
        content: Text(
            '"${s.title}" is deleted from the server and ${backend.nameFor(s.recipientEmail)} loses access.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok == true) await backend.deleteShare(s.id);
  }

  String _status() {
    switch (s.status) {
      case 'uploading':
        return 'Uploading...';
      case 'pending':
        return 'Waiting for accept';
      case 'accepted':
        return 'Accepted';
      default:
        return 'Declined';
    }
  }

  Widget _cell(String path, {String? more}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          netThumb(path, share: s),
          if (more != null)
            Container(
              color: Colors.black.withOpacity(0.5),
              alignment: Alignment.center,
              child: Text(more,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  Widget _mosaic() {
    if (locked) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 28),
            const SizedBox(height: 4),
            Text('${s.itemCount} photos hidden until you accept',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    return FutureBuilder<List<String>>(
      future: backend.pathsFor(s.id),
      builder: (context, snap) {
        final paths = snap.data;
        if (paths == null) {
          return Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }
        if (paths.isEmpty) {
          return const SizedBox(
              height: 70, child: Center(child: Text('No longer available')));
        }
        final n = paths.length;
        if (n == 1) {
          return SizedBox(height: 190, child: _cell(paths[0]));
        }
        if (n == 2) {
          return SizedBox(
            height: 150,
            child: Row(children: [
              Expanded(child: _cell(paths[0])),
              const SizedBox(width: 3),
              Expanded(child: _cell(paths[1])),
            ]),
          );
        }
        final shown = n > 4 ? 4 : n;
        return SizedBox(
          height: 190,
          child: Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(child: _cell(paths[0])),
                const SizedBox(width: 3),
                Expanded(child: _cell(paths[1])),
              ]),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Row(children: [
                Expanded(child: _cell(paths[2])),
                const SizedBox(width: 3),
                Expanded(
                  child: shown == 4
                      ? _cell(paths[3], more: n > 4 ? '+${n - 4}' : null)
                      : const SizedBox(),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final fg = mine ? Colors.white : (dark ? Colors.white : Colors.black87);
    final t = DateFormat('d MMM, h:mm a').format(s.createdAt);
    final width = MediaQuery.of(context).size.width * 0.78;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: PressScale(
          onTap: () {
            if (locked || s.status == 'uploading') return;
            Navigator.push(context, smoothRoute(SharedAlbumPage(share: s)));
          },
          onLongPress: mine ? _stop : null,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 6),
                bottomRight: Radius.circular(mine ? 6 : 20),
              ),
              gradient: mine
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, const Color(0xFF5E5CE6)],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: dark
                          ? [Colors.white.withOpacity(0.16), Colors.white.withOpacity(0.07)]
                          : [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.6)],
                    ),
              border: mine
                  ? null
                  : Border.all(
                      color: Colors.white.withOpacity(dark ? 0.2 : 0.9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.3 : 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mosaic(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                            '${s.itemCount} photos, ${s.allowDownload ? 'download allowed' : 'view only'}${s.encrypted ? ', encrypted' : ''}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(mine ? '${_status()}  $t' : t,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: fg.withOpacity(0.75))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!mine && s.status == 'pending')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy ? null : () => _answer(false),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: busy ? null : () => _answer(true),
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo picker (choose photos from your gallery to send)
// ---------------------------------------------------------------------------

class PhotoPickerPage extends StatefulWidget {
  final String title;
  const PhotoPickerPage({super.key, required this.title});

  @override
  State<PhotoPickerPage> createState() => _PhotoPickerPageState();
}

class _PhotoPickerPageState extends State<PhotoPickerPage> {
  final sel = SelectionController();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    sel.start(); // tapping a photo selects it
  }

  @override
  void dispose() {
    sel.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = store.groups;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: SelectionScope(
              ctrl: sel,
              scroll: scroll,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  GlassSliverBar(
                    title: Text(widget.title),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  for (final g in groups) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                        child: Text(
                          DateFormat('EEEE, d MMMM yyyy').format(g.date),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      sliver:
                          PhotoGridSliver(group: g, prefix: 'pick-', sel: sel),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
          DateScrollbar(scroll: scroll, groups: groups),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: sel,
        builder: (context, _) {
          final n = sel.count;
          return GlassBar(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: n == 0
                        ? null
                        : () => Navigator.pop(
                            context, store.selectedAssets(sel.selected)),
                    child: Text(n == 0 ? 'Select photos' : 'Next: $n photos'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
