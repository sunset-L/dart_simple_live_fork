import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 仅向左拖动时接管手势，向右拖动由外层标签页处理。
class HistorySwipeDelete extends StatefulWidget {
  const HistorySwipeDelete({
    required this.child,
    required this.onDelete,
    super.key,
  });

  final Widget child;
  final Future<void> Function() onDelete;

  @override
  State<HistorySwipeDelete> createState() => _HistorySwipeDeleteState();
}

class _HistorySwipeDeleteState extends State<HistorySwipeDelete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  double _width = 1;
  bool _confirmingDelete = false;

  void _onStart(DragStartDetails details) {
    if (_confirmingDelete) return;
    _swipe.stop();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_confirmingDelete) return;
    _swipe.value =
        (_swipe.value - details.delta.dx / _width).clamp(0.0, 1.0).toDouble();
  }

  Future<bool> _reset() async {
    try {
      await _swipe.animateBack(0, curve: Curves.easeOutCubic).orCancel;
      return mounted;
    } on TickerCanceled {
      return false;
    }
  }

  Future<void> _onEnd(DragEndDetails details) async {
    if (_confirmingDelete) return;
    final shouldDelete = _swipe.value >= 0.4;
    // 先回弹，再显示确认；短滑或取消不会删除记录。
    if (!await _reset() || !shouldDelete || !mounted) return;
    _confirmingDelete = true;
    try {
      await widget.onDelete();
    } finally {
      _confirmingDelete = false;
    }
  }

  void _onCancel() {
    _reset();
  }

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.gestureSettingsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
        return widget.child;
      }
      _width = constraints.maxWidth;
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _LeftOnlyHorizontalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  _LeftOnlyHorizontalDragRecognizer>(
            () => _LeftOnlyHorizontalDragRecognizer(),
            (recognizer) {
              recognizer
                ..gestureSettings = gestureSettings
                ..onlyAcceptDragOnThreshold = true
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd
                ..onCancel = _onCancel;
            },
          ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _swipe,
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: widget.child,
            ),
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Colors.red,
                    padding: const EdgeInsets.all(12),
                    alignment: Alignment.centerRight,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                ),
                Transform.translate(
                  offset: Offset(-_swipe.value * _width, 0),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// 默认 Dismissible 的水平识别器会抢占两个方向；此处只接受向左。
class _LeftOnlyHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved < 0 &&
        super.hasSufficientGlobalDistanceToAccept(
            pointerDeviceKind, deviceTouchSlop);
  }
}
