import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'store.dart';
import 'widgets.dart';

/// Draggable scroll handle on the right edge with a month/year bubble.
/// Appears while scrolling; drag it to jump quickly through your photos by date.
class DateScrollbar extends StatefulWidget {
  final ScrollController scroll;
  final List<DayGroup> groups;
  const DateScrollbar({super.key, required this.scroll, required this.groups});

  @override
  State<DateScrollbar> createState() => _DateScrollbarState();
}

class _DateScrollbarState extends State<DateScrollbar> {
  static const double _thumbH = 56;
  static const double _thumbW = 34;

  double _frac = 0;
  bool _visible = false;
  bool _dragging = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(DateScrollbar old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _onScroll() {
    if (_dragging) return; // the handle follows your finger while dragging
    final sc = widget.scroll;
    if (!sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    if (max <= 0) return;
    setState(() {
      _frac = (sc.offset / max).clamp(0.0, 1.0).toDouble();
      _visible = true;
    });
    _scheduleHide();
  }

  /// Month and year at a given point of the list (estimated from photo counts).
  String _label(double frac, double width) {
    final gs = widget.groups;
    if (gs.isEmpty) return '';
    final cols = gridColumns.value;
    final row = (width - 4) / cols + 2;
    double total = 0;
    final starts = <double>[];
    for (final g in gs) {
      starts.add(total);
      total += 86 + (g.assets.length / cols).ceil() * row;
    }
    final target = frac * total;
    var lo = 0, hi = gs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= target) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return DateFormat('MMM yyyy').format(gs[lo].date);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top + 58 + 16;
    final bottom = mq.padding.bottom + 120;

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, c) {
          final track = (c.maxHeight - top - bottom - _thumbH)
              .clamp(1.0, 100000.0)
              .toDouble();
          final y = top + _frac * track;
          final show = _visible || _dragging;

          return Stack(
            children: [
              Positioned(
                right: 4,
                top: y,
                child: IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (d) {
                        _hide?.cancel();
                        HapticFeedback.selectionClick();
                        setState(() {
                          _dragging = true;
                          _visible = true;
                        });
                      },
                      onVerticalDragUpdate: (d) {
                        final sc = widget.scroll;
                        if (!sc.hasClients) return;
                        final box = context.findRenderObject() as RenderBox;
                        final local = box.globalToLocal(d.globalPosition).dy;
                        final f = ((local - top - _thumbH / 2) / track)
                            .clamp(0.0, 1.0)
                            .toDouble();
                        setState(() => _frac = f);
                        sc.jumpTo(f * sc.position.maxScrollExtent);
                      },
                      onVerticalDragEnd: (_) {
                        setState(() => _dragging = false);
                        _scheduleHide();
                      },
                      onVerticalDragCancel: () {
                        setState(() => _dragging = false);
                        _scheduleHide();
                      },
                      child: Glass(
                        radius: 17,
                        child: SizedBox(
                          width: _thumbW,
                          height: _thumbH,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                              Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_dragging)
                Positioned(
                  right: _thumbW + 14,
                  top: y + _thumbH / 2 - 20,
                  child: IgnorePointer(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _label(_frac, c.maxWidth),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
