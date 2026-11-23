import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Smooth slide + fade page transition.
Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Photo thumbnail that fades in once loaded.
class PhotoThumb extends StatefulWidget {
  final AssetEntity asset;
  final int size;
  const PhotoThumb({super.key, required this.asset, this.size = 300});

  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

/// Remembers recent thumbnails so scrolling back is instant.
class _ThumbCache {
  static final Map<String, Uint8List> _m = <String, Uint8List>{};
  static const int _max = 600;

  static Uint8List? get(String k) {
    final v = _m.remove(k);
    if (v != null) _m[k] = v;
    return v;
  }

  static void put(String k, Uint8List v) {
    _m.remove(k);
    _m[k] = v;
    if (_m.length > _max) _m.remove(_m.keys.first);
  }
}

class _PhotoThumbState extends State<PhotoThumb> {
  Uint8List? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PhotoThumb old) {
    super.didUpdateWidget(old);
    if (old.size != widget.size || old.asset.id != widget.asset.id) _load();
  }

  void _load() {
    final asset = widget.asset;
    final size = widget.size;
    final key = '${asset.id}:$size';
    final hit = _ThumbCache.get(key);
    if (hit != null) {
      data = hit; // build runs right after, no flicker
      return;
    }
    asset.thumbnailDataWithSize(ThumbnailSize.square(size)).then((d) {
      if (d == null) return;
      _ThumbCache.put(key, d);
      if (mounted && asset.id == widget.asset.id && size == widget.size) {
        setState(() => data = d);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
      child: AnimatedOpacity(
        opacity: data == null ? 0 : 1,
        duration: const Duration(milliseconds: 280),
        child: data == null
            ? const SizedBox.expand()
            : Image.memory(data!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Tap target that gently shrinks while pressed.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: down ? 0.96 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Liquid Glass panel: translucent, blurred, with a soft highlight and edge.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.blur = 16,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.5 : 0.16),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [Colors.white.withOpacity(0.20), Colors.white.withOpacity(0.06)]
                    : [Colors.white.withOpacity(0.72), Colors.white.withOpacity(0.40)],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(dark ? 0.26 : 0.9),
                width: 1,
              ),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.3),
                colors: [
                  Colors.white.withOpacity(dark ? 0.16 : 0.5),
                  Colors.white.withOpacity(0),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Floating glass bar at the bottom of the screen (nav bar, selection bar...).
class GlassBar extends StatelessWidget {
  final Widget child;
  const GlassBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Glass(
          radius: 34,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: child,
        ),
      ),
    );
  }
}

/// Round glass button (used for Back).
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const GlassCircleButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Glass(
        radius: 23,
        child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 20)),
      ),
    );
  }
}

/// Large collapsing title with glass toolbar buttons. Replaces SliverAppBar.large.
class GlassSliverBar extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  const GlassSliverBar({
    super.key,
    required this.title,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _GlassHeader(
        title: title,
        actions: actions,
        topPad: MediaQuery.of(context).padding.top,
        canPop: Navigator.canPop(context),
        onBack: () => Navigator.maybePop(context),
        bg: Theme.of(context).scaffoldBackgroundColor,
        largeStyle: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}

class _GlassHeader extends SliverPersistentHeaderDelegate {
  final Widget title;
  final List<Widget> actions;
  final double topPad;
  final bool canPop;
  final VoidCallback onBack;
  final Color bg;
  final TextStyle? largeStyle;

  _GlassHeader({
    required this.title,
    required this.actions,
    required this.topPad,
    required this.canPop,
    required this.onBack,
    required this.bg,
    required this.largeStyle,
  });

  static const double _bar = 58;
  static const double _large = 62;

  @override
  double get minExtent => topPad + _bar;

  @override
  double get maxExtent => topPad + _bar + _large;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / _large).clamp(0.0, 1.0);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;

    return Stack(
      children: [
        // frosted background fades in as the title collapses
        Positioned.fill(
          child: Opacity(
            opacity: t,
            child: Container(
              decoration: BoxDecoration(
                color: bg.withOpacity(0.94),
                border: Border(
                  bottom: BorderSide(color: ink.withOpacity(0.08)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: topPad,
          left: 10,
          right: 10,
          height: _bar,
          child: Row(
            children: [
              if (canPop)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassCircleButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack,
                  ),
                ),
              Expanded(
                child: Opacity(
                  opacity: t,
                  child: Padding(
                    padding: EdgeInsets.only(left: canPop ? 0 : 10),
                    child: DefaultTextStyle(
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title,
                    ),
                  ),
                ),
              ),
              if (actions.isNotEmpty)
                Glass(
                  radius: 23,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    height: 46,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 6,
          child: Opacity(
            opacity: 1 - t,
            child: Transform.translate(
              offset: Offset(0, 8 * t),
              child: DefaultTextStyle(
                style: largeStyle ??
                    TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w700, color: ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _GlassHeader old) => true;
}

/// Soft coloured glow behind pages that have no photos (so glass has something to refract).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.34 : 0.24;
    Widget blob(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [c.withOpacity(a), c.withOpacity(0)],
            ),
          ),
        );
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: -120, left: -100, child: blob(const Color(0xFF0A84FF), 420)),
          Positioned(top: 280, right: -170, child: blob(const Color(0xFFBF5AF2), 470)),
          Positioned(bottom: -150, left: -60, child: blob(const Color(0xFF30D158), 430)),
        ],
      ),
    );
  }
}

/// Pinch, double-tap and pan zoom for one image. Tells the parent when zoomed in.
class ZoomableImage extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onZoomChanged;
  final VoidCallback? onTap;
  const ZoomableImage({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.onTap,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  List<double> _a = List<double>.filled(16, 0);
  List<double> _b = List<double>.filled(16, 0);
  bool _zoomed = false;
  Offset _tapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_check);
    _anim.addListener(_tick);
  }

  @override
  void dispose() {
    _tc.removeListener(_check);
    _tc.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _check() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.02;
    if (z != _zoomed) {
      _zoomed = z;
      widget.onZoomChanged?.call(z);
    }
  }

  void _tick() {
    final t = Curves.easeOutCubic.transform(_anim.value);
    _tc.value = Matrix4.fromList(
      List<double>.generate(16, (i) => lerpDouble(_a[i], _b[i], t)!),
    );
  }

  void _doubleTap() {
    const s = 2.6;
    final target = _zoomed
        ? Matrix4.identity()
        : Matrix4.fromList(<double>[
            s, 0, 0, 0,
            0, s, 0, 0,
            0, 0, 1, 0,
            _tapPos.dx * (1 - s), _tapPos.dy * (1 - s), 0, 1,
          ]);
    _a = _tc.value.storage.toList();
    _b = target.storage.toList();
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tapPos = d.localPosition,
      onDoubleTap: _doubleTap,
      onTap: widget.onTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        child: widget.child,
      ),
    );
  }
}
