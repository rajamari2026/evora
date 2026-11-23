import 'dart:typed_data';

import 'package:flutter/cupertino.dart'
    show CupertinoSlidingSegmentedControl, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import 'backend.dart';
import 'chat_pages.dart';
import 'store.dart';
import 'widgets.dart';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}

InputDecoration _field(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );

// ---------------------------------------------------------------------------
// Shared tab
// ---------------------------------------------------------------------------

class SharedTab extends StatelessWidget {
  const SharedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        if (!backend.ready) {
          return const _InfoScroll(
            icon: Icons.cloud_off_rounded,
            title: 'Sharing is not set up yet',
            body:
                'Add your Supabase URL and key in lib/config.dart. The steps are in README.md under "Set up sharing".',
          );
        }
        if (!backend.loggedIn) return const _LoginView();
        return const _SharedHome();
      },
    );
  }
}

class _InfoScroll extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoScroll(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const GlassSliverBar(title: Text('Shared')),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 52, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool create = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e = email.text.trim();
    if (!e.contains('@') || pass.text.length < 6) {
      setState(() => error = 'Enter a valid email and a password of 6+ characters.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final err = create
        ? await backend.signUp(e, pass.text)
        : await backend.signIn(e, pass.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
    if (err == null) backend.refreshShares();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return CustomScrollView(
      slivers: [
        const GlassSliverBar(title: Text('Shared')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(create ? 'Create your account' : 'Sign in to share',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'People you share with sign in with their own email. They see photos only after they accept.',
                  style: t.bodyMedium
                      ?.copyWith(color: t.bodyMedium?.color?.withOpacity(0.7)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _field('Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: _field('Password'),
                  onSubmitted: (_) => _submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(create ? 'Create account' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      create = !create;
                      error = null;
                    }),
                    child: Text(create
                        ? 'I already have an account'
                        : 'Create a new account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared home (requests / shared with me / my shares)
// ---------------------------------------------------------------------------

class _SharedHome extends StatefulWidget {
  const _SharedHome();

  @override
  State<_SharedHome> createState() => _SharedHomeState();
}

class _SharedHomeState extends State<_SharedHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => backend.refreshShares());
  }

  @override
  Widget build(BuildContext context) => const ChatList();
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.6))),
        ),
      );
}

BoxDecoration _cardDecoration(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(24),
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
        color: Colors.black.withOpacity(dark ? 0.35 : 0.08),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _RequestCard extends StatefulWidget {
  final ShareRow share;
  const _RequestCard({required this.share});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool busy = false;

  Future<void> _answer(bool accept) async {
    HapticFeedback.mediumImpact();
    setState(() => busy = true);
    final err = await backend.respond(widget.share.id, accept);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) _toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.share;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.ownerEmail} wants to share',
              style: t.bodySmall
                  ?.copyWith(color: t.bodySmall?.color?.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(s.title,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              '${s.itemCount} photos, ${s.allowDownload ? 'download allowed' : 'view only'}',
              style: t.bodySmall),
          const SizedBox(height: 14),
          Row(
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
        ],
      ),
    );
  }
}

class _ShareRowTile extends StatelessWidget {
  final ShareRow share;
  final bool mine;
  const _ShareRowTile({required this.share, required this.mine});

  (String, Color) _status() {
    switch (share.status) {
      case 'uploading':
        return ('Uploading', Colors.grey);
      case 'pending':
        return ('Waiting for accept', const Color(0xFFFF9F0A));
      case 'accepted':
        return ('Accepted', const Color(0xFF30D158));
      default:
        return ('Declined', const Color(0xFFFF453A));
    }
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Stop sharing?'),
        content: Text(
            '"${share.title}" will be deleted from the server and ${share.recipientEmail} will lose access.'),
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
    if (ok != true) return;
    final err = await backend.deleteShare(share.id);
    if (context.mounted && err != null) _toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (label, color) = _status();
    final canOpen = mine ? share.status != 'uploading' : true;
    return PressScale(
      onTap: () {
        if (canOpen) {
          Navigator.push(context, smoothRoute(SharedAlbumPage(share: share)));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: _cardDecoration(context),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.photo_library_rounded,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(share.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      mine
                          ? 'To ${share.recipientEmail}'
                          : 'From ${share.ownerEmail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${share.itemCount} photos', style: t.bodySmall),
                      if (mine) ...[
                        const SizedBox(width: 8),
                        Text(label,
                            style: t.bodySmall?.copyWith(
                                color: color, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (mine)
              IconButton(
                tooltip: 'Stop sharing',
                onPressed: () => _stop(context),
                icon: const Icon(Icons.delete_outline_rounded),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared album view
// ---------------------------------------------------------------------------

Widget _netImage(String path,
    {int? cacheWidth, BoxFit fit = BoxFit.cover, ShareRow? share}) {
  if (share != null && share.encrypted) {
    return SharePhoto(share: share, path: path, fit: fit, cacheWidth: cacheWidth);
  }
  return Image.network(
    backend.imgUrl(path),
    headers: backend.imgHeaders,
    fit: fit,
    cacheWidth: cacheWidth,
    gaplessPlayback: true,
    frameBuilder: (c, child, frame, sync) => AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 260),
      child: child,
    ),
    errorBuilder: (_, __, ___) => const ColoredBox(
      color: Color(0x22888888),
      child: Center(child: Icon(Icons.broken_image_outlined)),
    ),
  );
}

/// Small thumbnail (fast). Older shares without thumbnails fall back to the photo.
Widget netThumb(String path, {BoxFit fit = BoxFit.cover, ShareRow? share}) {
  if (share != null && share.encrypted) {
    return SharePhoto(
        share: share,
        path: thumbPathOf(path),
        fallbackPath: path,
        fit: fit,
        cacheWidth: 360);
  }
  return Image.network(
    backend.imgUrl(thumbPathOf(path)),
    headers: backend.imgHeaders,
    fit: fit,
    cacheWidth: 360,
    gaplessPlayback: true,
    frameBuilder: (c, child, frame, sync) => AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: child,
    ),
    errorBuilder: (_, __, ___) => _netImage(path, cacheWidth: 360, fit: fit),
  );
}

/// A photo from an end-to-end encrypted share, decrypted on this device.
class SharePhoto extends StatefulWidget {
  final ShareRow share;
  final String path;
  final String? fallbackPath;
  final BoxFit fit;
  final int? cacheWidth;
  const SharePhoto({
    super.key,
    required this.share,
    required this.path,
    this.fallbackPath,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  @override
  State<SharePhoto> createState() => _SharePhotoState();
}

class _SharePhotoState extends State<SharePhoto> {
  Uint8List? data;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var d = await backend.plainBytes(widget.share, widget.path);
    if (d == null && widget.fallbackPath != null) {
      d = await backend.plainBytes(widget.share, widget.fallbackPath!);
    }
    if (!mounted) return;
    setState(() {
      data = d;
      failed = d == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d != null) {
      return Image.memory(d,
          fit: widget.fit, cacheWidth: widget.cacheWidth, gaplessPlayback: true);
    }
    return ColoredBox(
      color: const Color(0x22888888),
      child: Center(
        child: failed
            ? Icon(backend.e2eeReady
                ? Icons.broken_image_outlined
                : Icons.lock_outline_rounded)
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

/// Turn on private sharing (first time) or unlock it on this device.
Future<bool> showE2eeSetup(BuildContext context) async {
  final hasBackup = await backend.serverHasBackup();
  if (!context.mounted) return false;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final pass = TextEditingController();
  final again = TextEditingController();
  String? error;
  var busy = false;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: false,
    backgroundColor: dark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_rounded),
                  const SizedBox(width: 8),
                  Text(hasBackup ? 'Unlock private sharing' : 'Turn on private sharing',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                hasBackup
                    ? 'Enter your encryption passcode to open private photos on this device.'
                    : 'Photos are locked on your phone and only the receiver can open them, not even the server. Choose an encryption passcode (at least 8 characters). If you forget it, private photos cannot be recovered.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pass,
                obscureText: true,
                enabled: !busy,
                decoration: _field('Encryption passcode'),
              ),
              if (!hasBackup) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: again,
                  obscureText: true,
                  enabled: !busy,
                  decoration: _field('Repeat passcode'),
                ),
              ],
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
                  onPressed: busy
                      ? null
                      : () async {
                          if (pass.text.length < 8) {
                            setSheet(() => error = 'Use at least 8 characters.');
                            return;
                          }
                          if (!hasBackup && pass.text != again.text) {
                            setSheet(() => error = 'The passcodes do not match.');
                            return;
                          }
                          setSheet(() {
                            busy = true;
                            error = null;
                          });
                          final err = hasBackup
                              ? await backend.unlockEncryption(pass.text)
                              : await backend.setupEncryption(pass.text);
                          if (err != null) {
                            setSheet(() {
                              busy = false;
                              error = err;
                            });
                          } else if (ctx.mounted) {
                            Navigator.pop(ctx, true);
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(hasBackup ? 'Unlock' : 'Turn on'),
                ),
              ),
              if (!busy)
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Not now'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

Future<bool> _saveToGallery(String path, [ShareRow? share]) async {
  try {
    final bytes = share != null
        ? await backend.plainBytes(share, path)
        : await backend.fetchBytes(path);
    if (bytes == null) return false;
    await PhotoManager.editor.saveImage(
      bytes,
      filename: 'Evora_${DateTime.now().microsecondsSinceEpoch}.jpg',
      relativePath: 'Pictures/Evora',
    );
    return true;
  } catch (_) {
    return false;
  }
}

class SharedAlbumPage extends StatefulWidget {
  final ShareRow share;
  const SharedAlbumPage({super.key, required this.share});

  @override
  State<SharedAlbumPage> createState() => _SharedAlbumPageState();
}

class _SharedAlbumPageState extends State<SharedAlbumPage> {
  List<String>? paths;
  bool saving = false;

  bool get canDownload =>
      widget.share.allowDownload && widget.share.ownerId != backend.userId;

  @override
  void initState() {
    super.initState();
    backend.fetchItemPaths(widget.share.id).then((p) {
      if (mounted) setState(() => paths = p);
    });
  }

  Future<void> _downloadAll() async {
    final list = paths;
    if (list == null || list.isEmpty) return;
    setState(() => saving = true);
    var ok = 0;
    for (final p in list) {
      if (await _saveToGallery(p, widget.share)) ok++;
    }
    if (!mounted) return;
    setState(() => saving = false);
    _toast(context, 'Saved $ok of ${list.length} photos to your gallery.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = paths;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          GlassSliverBar(
            title: Text(widget.share.title),
            actions: [
              if (canDownload)
                saving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5)),
                      )
                    : IconButton(
                        tooltip: 'Save all',
                        onPressed: _downloadAll,
                        icon: const Icon(Icons.download_rounded),
                      ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                widget.share.ownerId == backend.userId
                    ? 'Shared with ${widget.share.recipientEmail}'
                    : 'From ${widget.share.ownerEmail}  ${canDownload ? 'Download allowed' : 'View only'}',
                style: t.bodyMedium
                    ?.copyWith(color: t.bodyMedium?.color?.withOpacity(0.7)),
              ),
            ),
          ),
          if (list == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('This album is no longer available.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (c, i) => GestureDetector(
                    onTap: () => Navigator.push(
                      c,
                      smoothRoute(_NetViewer(
                          paths: list,
                          index: i,
                          canDownload: canDownload,
                          share: widget.share)),
                    ),
                    child: Hero(
                      tag: 'net-${list[i]}',
                      child: netThumb(list[i], share: widget.share),
                    ),
                  ),
                  childCount: list.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

class _NetViewer extends StatefulWidget {
  final List<String> paths;
  final int index;
  final bool canDownload;
  final ShareRow share;
  const _NetViewer(
      {required this.paths,
      required this.index,
      required this.canDownload,
      required this.share});

  @override
  State<_NetViewer> createState() => _NetViewerState();
}

class _NetViewerState extends State<_NetViewer> {
  late final PageController pc = PageController(initialPage: widget.index);
  late int cur = widget.index;
  bool zoomed = false;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    final ok = await _saveToGallery(widget.paths[cur], widget.share);
    if (mounted) _toast(context, ok ? 'Saved to your gallery.' : 'Could not save.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: pc,
            physics: zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.paths.length,
            onPageChanged: (i) => setState(() {
              cur = i;
              zoomed = false;
            }),
            itemBuilder: (_, i) => ZoomableImage(
              onZoomChanged: (z) {
                if (i == cur && z != zoomed) setState(() => zoomed = z);
              },
              child: Center(
                child: Hero(
                  tag: 'net-${widget.paths[i]}',
                  child: _netImage(widget.paths[i],
                      fit: BoxFit.contain, share: widget.share),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  8, MediaQuery.of(context).padding.top + 4, 8, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text('${cur + 1} / ${widget.paths.length}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (widget.canDownload)
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.download_rounded),
                      onPressed: _save,
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share composer (sender side, with confirmation step)
// ---------------------------------------------------------------------------

class ShareComposer {
  static Future<bool> _ensureSignedIn(BuildContext context) async {
    if (backend.ready && backend.loggedIn) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Sign in first'),
        content: Text(backend.ready
            ? 'Open the Shared tab, sign in, then select your photos again.'
            : 'Sharing is not set up yet. See README.md.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Shared')),
        ],
      ),
    );
    if (go == true && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      tabIndex.value = 2;
    }
    return false;
  }

  /// From the Library: pick who to send to (saved contacts or a new email).
  static Future<void> open(
    BuildContext context,
    List<AssetEntity> assets, {
    VoidCallback? onDone,
  }) async {
    if (assets.isEmpty) return;
    if (!await _ensureSignedIn(context)) return;
    if (!context.mounted) return;
    await _show(context, assets, null, onDone);
  }

  /// From a chat: the person is already known, nothing to type.
  static Future<void> sendTo(
    BuildContext context,
    String email,
    List<AssetEntity> assets, {
    VoidCallback? onDone,
  }) async {
    if (assets.isEmpty) return;
    if (!await _ensureSignedIn(context)) return;
    if (!context.mounted) return;
    await _show(context, assets, email, onDone);
  }

  static Future<void> _show(BuildContext context, List<AssetEntity> assets,
      String? fixedEmail, VoidCallback? onDone) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      backgroundColor: dark ? const Color(0xF21C1C1E) : const Color(0xF2FFFFFF),
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ComposerSheet(
          assets: assets, fixedEmail: fixedEmail, onDone: onDone),
    );
  }
}

class _ComposerSheet extends StatefulWidget {
  final List<AssetEntity> assets;
  final String? fixedEmail;
  final VoidCallback? onDone;
  const _ComposerSheet({required this.assets, this.fixedEmail, this.onDone});

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final title = TextEditingController(text: 'Photos');
  final to = TextEditingController();
  final nameCtl = TextEditingController();
  bool allow = false;
  late bool secure = backend.e2eeReady;
  bool sending = false;
  int done = 0;
  String? error;

  @override
  void dispose() {
    title.dispose();
    to.dispose();
    nameCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = (widget.fixedEmail ?? to.text).trim().toLowerCase();
    final name = title.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => error = "Enter the receiver's email address.");
      return;
    }
    if (name.isEmpty) {
      setState(() => error = 'Give this share a name.');
      return;
    }
    if (email == backend.email) {
      setState(() => error = 'Use a different email than your own.');
      return;
    }

    // Verification step 1: sender confirms.
    final shown = backend.nameFor(email);
    var useE2ee = secure;
    if (useE2ee) {
      final pub = await backend.publicKeyOf(email);
      if (!mounted) return;
      if (pub == null) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('No private sharing yet'),
            content: Text(
                '$shown has not turned on private sharing, so these photos cannot be end-to-end encrypted for them. Send without encryption?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Send without encryption')),
            ],
          ),
        );
        if (go != true || !mounted) return;
        useE2ee = false;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Send ${widget.assets.length} photos?'),
        content: Text(
            'To: $shown ($email)\nAccess: ${allow ? 'view and download' : 'view only'}\nEncryption: ${useE2ee ? 'end-to-end' : 'none'}\n\nThey can see nothing until they accept. You can stop sharing any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm and send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() {
      sending = true;
      error = null;
      done = 0;
    });
    final err = await backend.createShare(
      to: email,
      title: name,
      allowDownload: allow,
      assets: widget.assets,
      onProgress: (d, t) {
        if (mounted) setState(() => done = d);
      },
      encrypt: useE2ee,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        sending = false;
        error = err;
      });
      return;
    }
    // remember the person, so next time only their name is shown
    if (!backend.contacts.containsKey(email) || nameCtl.text.trim().isNotEmpty) {
      await backend.saveContact(email, nameCtl.text);
    }
    store.markSentIds(widget.assets.map((a) => a.id));
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Sent to $shown. Waiting for them to accept.'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = widget.assets.length;
    final fixed = widget.fixedEmail;
    final people = backend.chatEmails;
    return PopScope(
      canPop: !sending,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fixed == null
                  ? 'Share $n photos'
                  : 'Send $n photos to ${backend.nameFor(fixed)}',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                enabled: !sending,
                textCapitalization: TextCapitalization.words,
                decoration: _field('Share name'),
              ),
              if (fixed == null) ...[
                if (people.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('People', style: t.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in people.take(10))
                        ActionChip(
                          avatar: ChatAvatar(name: backend.nameFor(e), size: 22),
                          label: Text(backend.nameFor(e)),
                          onPressed: sending
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  setState(() => to.text = e);
                                },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: to,
                  enabled: !sending,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _field('Receiver email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtl,
                  enabled: !sending,
                  textCapitalization: TextCapitalization.words,
                  decoration: _field('Name for this person (optional)'),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.lock_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text('End-to-end encrypted',
                                style: t.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text(
                            secure
                                ? 'Only the receiver can open these photos'
                                : 'Not encrypted',
                            style: t.bodySmall),
                      ],
                    ),
                  ),
                  CupertinoSwitch(
                    value: secure,
                    onChanged: sending
                        ? null
                        : (v) async {
                            HapticFeedback.selectionClick();
                            if (v && !backend.e2eeReady) {
                              final ok = await showE2eeSetup(context);
                              if (mounted) setState(() => secure = ok);
                            } else {
                              setState(() => secure = v);
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Allow download',
                            style: t.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(allow ? 'They can save photos' : 'View only (no save button, lower quality)',
                            style: t.bodySmall),
                      ],
                    ),
                  ),
                  CupertinoSwitch(
                    value: allow,
                    onChanged: sending
                        ? null
                        : (v) {
                            HapticFeedback.selectionClick();
                            setState(() => allow = v);
                          },
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 14),
              if (sending) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: n == 0 ? null : done / n, minHeight: 6),
                ),
                const SizedBox(height: 8),
                Text('Uploading $done of $n. Keep the app open.',
                    style: t.bodySmall),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _send,
                    child: const Text('Review and send'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
