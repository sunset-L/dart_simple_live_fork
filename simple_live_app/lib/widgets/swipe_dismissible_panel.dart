import 'package:flutter/material.dart';

/// 让第一页的右滑拖动整个弹窗，超过半宽或快速右滑松手时关闭。
class SwipeDismissiblePanel extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;

  const SwipeDismissiblePanel({
    required this.child,
    required this.onDismiss,
    super.key,
  });

  /// PageView 关闭 pageSnapping，交由此 physics 保留翻页和处理弹窗拖动。
  static ScrollPhysics pagePhysicsOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_PanelScope>()
            ?.state
            .physics ??
        const PageScrollPhysics(parent: ClampingScrollPhysics());
  }

  @override
  State<SwipeDismissiblePanel> createState() => _SwipeDismissiblePanelState();
}

class _SwipeDismissiblePanelState extends State<SwipeDismissiblePanel>
    with SingleTickerProviderStateMixin {
  static const _minDismissVelocity = 700.0;

  final _panelKey = GlobalKey();
  late final _offset = AnimationController.unbounded(vsync: this);
  late final physics = _PanelScrollPhysics(
    state: this,
    parent: const PageScrollPhysics(parent: ClampingScrollPhysics()),
  );
  int? _pointer;
  bool _dragFromFirstPage = false;
  bool _settling = false;
  bool _closing = false;

  double get _width => _panelKey.currentContext?.size?.width ?? 0;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics is! PageMetrics ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        !_closing) {
      _offset.stop();
      _settling = false;
      _dragFromFirstPage = notification.metrics.pixels <=
          notification.metrics.minScrollExtent + 0.01;
    }
    if (notification is ScrollEndNotification) {
      _finishDrag();
      _dragFromFirstPage = false;
    }
    return false;
  }

  double _consumeDrag(ScrollMetrics position, double delta) {
    if (_closing) {
      return 0;
    }
    if (!_dragFromFirstPage ||
        _pointer == null ||
        (_offset.value == 0 &&
            (delta <= 0 ||
                position.pixels > position.minScrollExtent + 0.01))) {
      return delta;
    }
    final previous = _offset.value;
    _offset.value = (previous + delta).clamp(0.0, _width).toDouble();
    // 拖回原位后的剩余左滑距离，继续交给 PageView 翻到历史页。
    return delta - (_offset.value - previous);
  }

  void _finishDrag({bool canceled = false, double velocity = 0}) {
    if (_offset.value == 0 || _settling || _closing || _pointer != null) {
      return;
    }
    _settling = true;
    _closing = !canceled &&
        (_offset.value > _width / 2 || velocity >= _minDismissVelocity);
    _offset
        .animateTo(
      _closing ? _width : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    )
        .then((_) {
      if (!mounted) {
        return;
      }
      _settling = false;
      if (_closing) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pointer ??= event.pointer;
      },
      onPointerUp: (event) {
        if (_pointer == event.pointer) {
          _pointer = null;
        }
      },
      onPointerCancel: (event) {
        if (_pointer == event.pointer) {
          _pointer = null;
          _finishDrag(canceled: true);
          _dragFromFirstPage = false;
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _PanelScope(
          state: this,
          child: AnimatedBuilder(
            animation: _offset,
            child: KeyedSubtree(key: _panelKey, child: widget.child),
            builder: (_, child) => Transform.translate(
              offset: Offset(_offset.value, 0),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelScope extends InheritedWidget {
  final _SwipeDismissiblePanelState state;

  const _PanelScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_PanelScope oldWidget) => state != oldWidget.state;
}

class _PanelScrollPhysics extends ScrollPhysics {
  final _SwipeDismissiblePanelState state;

  const _PanelScrollPhysics({required this.state, super.parent});

  @override
  _PanelScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _PanelScrollPhysics(state: state, parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return state._consumeDrag(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (state._offset.value > 0 || state._closing) {
      // PageView 的滚动速度与手指拖动方向相反，负速度表示向右甩动。
      state._finishDrag(velocity: -velocity);
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
