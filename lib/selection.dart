import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'widgets.dart';

/// Holds which photos are selected.
class SelectionController extends ChangeNotifier {
  bool active = false;
  final Set<String> selected = {};

  int get count => selected.length;
  bool isSelected(String id) => selected.contains(id);

  void start() {
    if (active) return;
    active = true;
    HapticFeedback.selectionClick();
    notifyListeners();
  }

  void clear() {
    active = false;
    selected.clear();
    notifyListeners();
  }

  void toggle(String id) {
    HapticFeedback.selectionClick();
    if (!selected.remove(id)) selected.add(id);
    notifyListeners();
  }

  void setSelected(String id, bool on) {
    final changed = on ? selected.add(id) : selected.remove(id);
    if (changed) {
      HapticFeedback.selectionClick();
      notifyListeners();
    }
  }

  void addAll(Iterable<String> ids) {
    selected.addAll(ids);
    notifyListeners();
  }

  void removeAll(Iterable<String> ids) {
    selected.removeAll(ids);
    notifyListeners();
  }
}

/// Scroll behaviour that can freeze scrolling while two fingers pinch.
class _ScopeBehavior extends MaterialScrollBehavior {
  final bool locked;
  const _ScopeBehavior(this.locked);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => locked
      ? const NeverScrollableScrollPhysics()
      : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  bool shouldNotify(covariant _ScopeBehavior old) => old.locked != locked;
}

/// Wraps a scroll view and adds:
///  - swipe to select: while in Select mode, drag sideways across photos
///  - long-press a photo, then drag in any direction to select
///  - pinch with two fingers to change the tile size (1 to 7 columns)
class SelectionScope extends StatefulWidget {
  final SelectionController ctrl;
  final ScrollController scroll;
  final Widget child;
  const SelectionScope({
    super.key,
    required this.ctrl,
    required this.scroll,
    required this.child,
  });

  @override
  State<SelectionScope> createState() => _SelectionScopeState();
}

class _SelectionScopeState extends State<SelectionScope>
    with SingleTickerProviderStateMixin {
  // selection drag
  Offset? _pos;
  Offset? _origin;
  bool _moved = false;
  bool? _selecting;
  Timer? _timer;

  // pinch
  final Map<int, Offset> _ptrs = {};
  Offset? _downPos;
  double _startDist = 0;
  int _startCols = 3;
  int _previewCols = 3;
  bool _pinching = false;
  Alignment _focal = Alignment.center;
  final ValueNotifier<double> _zoom = ValueNotifier<double>(1.0);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  double _from = 1.0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      _zoom.value =
          _from + (1 - _from) * Curves.easeOutCubic.transform(_settle.value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _settle.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// Finds the photo id under a screen position (tiles are wrapped in MetaData).
  String? _hit(Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance
        .hitTestInView(result, global, View.of(context).viewId);
    for (final e in result.path) {
      final t = e.target;
      if (t is RenderMetaData && t.metaData is String) {
        return t.metaData as String;
      }
    }
    return null;
  }

  void _apply() {
    final p = _pos;
    final s = _selecting;
    if (p == null || s == null) return;
    final id = _hit(p);
    if (id != null) widget.ctrl.setSelected(id, s);
  }

  void _begin(Offset p) {
    widget.ctrl.start();
    _pos = p;
    _origin = p;
    _moved = false;
    final id = _hit(p);
    _selecting = id == null ? true : !widget.ctrl.isSelected(id);
    if (id != null) widget.ctrl.setSelected(id, _selecting!);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _update(Offset p) {
    _pos = p;
    final o = _origin;
    if (!_moved && o != null && (p - o).distance > 24) _moved = true;
    _apply();
  }

  void _end() {
    _timer?.cancel();
    _selecting = null;
    _pos = null;
    _origin = null;
    _moved = false;
  }

  // long press, then drag anywhere
  void _lpStart(LongPressStartDetails d) {
    _begin(d.globalPosition);
    HapticFeedback.mediumImpact();
  }

  // sideways swipe in Select mode
  void _dragStart(DragStartDetails d) {
    _begin(_downPos ?? d.globalPosition);
    _update(d.globalPosition);
  }

  void _tick() {
    final p = _pos;
    final sc = widget.scroll;
    if (p == null || !_moved || !sc.hasClients || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pad = MediaQuery.of(context).padding;
    final top = box.localToGlobal(Offset.zero).dy;
    final h = box.size.height;
    final topLimit = top + pad.top + 110;
    final bottomLimit = top + h - pad.bottom - 110;
    const ramp = 70.0, maxSpeed = 14.0;
    double speed = 0;
    if (p.dy < topLimit) {
      speed = -((topLimit - p.dy) / ramp).clamp(0.0, 1.0) * maxSpeed;
    } else if (p.dy > bottomLimit) {
      speed = ((p.dy - bottomLimit) / ramp).clamp(0.0, 1.0) * maxSpeed;
    }
    if (speed != 0) {
      final pos = sc.position;
      final target =
          (sc.offset + speed).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      sc.jumpTo(target.toDouble());
      _apply();
    }
  }

  // ---- smooth pinch zoom -------------------------------------------------
  // While you pinch, the whole grid scales smoothly under your fingers.
  // When you let go it snaps to the nearest column count with an animation.

  double _dist() {
    final p = _ptrs.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  Alignment _focalAlign() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return Alignment.center;
    final ps = _ptrs.values.take(2).toList();
    final mid = (ps[0] + ps[1]) / 2;
    final local = box.globalToLocal(mid);
    return Alignment(
      (local.dx / box.size.width) * 2 - 1,
      (local.dy / box.size.height) * 2 - 1,
    );
  }

  void _down(PointerDownEvent e) {
    _ptrs[e.pointer] = e.position;
    if (_ptrs.length == 1) _downPos = e.position;
    if (_ptrs.length == 2) {
      _settle.stop();
      _zoom.value = 1.0;
      _startDist = _dist();
      _startCols = gridColumns.value;
      _previewCols = _startCols;
      _focal = _focalAlign();
      _end();
      setState(() => _pinching = true);
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.position;
    if (!_pinching || _ptrs.length < 2 || _startDist < 30) return;
    final ratio = _dist() / _startDist;
    _zoom.value = ratio.clamp(0.45, 2.6).toDouble();
    final cols = (_startCols / ratio).round().clamp(1, 7).toInt();
    if (cols != _previewCols) {
      _previewCols = cols;
      HapticFeedback.selectionClick();
    }
  }

  void _up(PointerEvent e) {
    _ptrs.remove(e.pointer);
    if (_ptrs.isEmpty) _downPos = null;
    if (_pinching && _ptrs.length < 2) {
      final live = _zoom.value;
      final target = _previewCols;
      // keep the picture continuous across the relayout
      final s0 = (live * target / _startCols).clamp(0.4, 3.0).toDouble();
      gridColumns.value = target;
      _from = s0;
      _zoom.value = s0;
      _settle.forward(from: 0);
      setState(() => _pinching = false);
      store.saveColumns();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _pointerMove,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: ListenableBuilder(
        listenable: widget.ctrl,
        child: ListenableBuilder(
          listenable: _zoom,
          child: ScrollConfiguration(
            behavior: _ScopeBehavior(_pinching),
            child: widget.child,
          ),
          builder: (context, inner) => Transform.scale(
            scale: _zoom.value,
            alignment: _focal,
            child: inner,
          ),
        ),
        builder: (context, child) {
          final on = widget.ctrl.active;
          return GestureDetector(
            onLongPressStart: _lpStart,
            onLongPressMoveUpdate: (d) => _update(d.globalPosition),
            onLongPressEnd: (_) => _end(),
            onLongPressCancel: _end,
            onHorizontalDragStart: on ? _dragStart : null,
            onHorizontalDragUpdate: on ? (d) => _update(d.globalPosition) : null,
            onHorizontalDragEnd: on ? (_) => _end() : null,
            onHorizontalDragCancel: on ? _end : null,
            child: child,
          );
        },
      ),
    );
  }
}

/// Bottom bar shown while selecting.
class SelectionBar extends StatelessWidget {
  final SelectionController sel;
  final VoidCallback onWhatsApp;
  final VoidCallback onInApp;
  final VoidCallback onAddToEvent;
  final VoidCallback onMarkSent;
  final VoidCallback onClearSent;
  final VoidCallback onDelete;
  final VoidCallback? onRemove;
  const SelectionBar({
    super.key,
    required this.sel,
    required this.onWhatsApp,
    required this.onInApp,
    required this.onAddToEvent,
    required this.onMarkSent,
    required this.onClearSent,
    required this.onDelete,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sel,
      builder: (context, _) {
        final n = sel.count;
        final off = n == 0;
        final accent = Theme.of(context).colorScheme.primary;
        return GlassBar(
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                onPressed: sel.clear,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                // scales down on narrow phones so nothing overflows
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '$n',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17),
                        ),
                      ),
                      _BarAction(
                        icon: Icons.send_rounded,
                        label: 'WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: off ? null : onWhatsApp,
                      ),
                      _BarAction(
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        color: accent,
                        onTap: off ? null : onInApp,
                      ),
                      _BarAction(
                        icon: Icons.add_to_photos_rounded,
                        label: 'Event',
                        color: const Color(0xFFBF5AF2),
                        onTap: off ? null : onAddToEvent,
                      ),
                      if (onRemove != null)
                        _BarAction(
                          icon: Icons.remove_circle_outline_rounded,
                          label: 'Remove',
                          color: const Color(0xFFFF9F0A),
                          onTap: off ? null : onRemove,
                        ),
                      _MoreAction(
                        enabled: !off,
                        onMarkSent: onMarkSent,
                        onClearSent: onClearSent,
                        onDelete: onDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MoreAction extends StatelessWidget {
  final bool enabled;
  final VoidCallback onMarkSent;
  final VoidCallback onClearSent;
  final VoidCallback onDelete;
  const _MoreAction({
    required this.enabled,
    required this.onMarkSent,
    required this.onClearSent,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: IgnorePointer(
        ignoring: !enabled,
        child: PopupMenuButton<String>(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (v) {
            if (v == 'sent') onMarkSent();
            if (v == 'unsent') onClearSent();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'sent', child: Text('Mark as sent')),
            PopupMenuItem(value: 'unsent', child: Text('Clear sent mark')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Move to Recently Deleted',
                  style: TextStyle(color: Color(0xFFFF453A))),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz_rounded, color: color, size: 25),
                const SizedBox(height: 2),
                Text('More',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _BarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: IgnorePointer(
        ignoring: onTap == null,
        child: PressScale(
          onTap: onTap ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 25),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
