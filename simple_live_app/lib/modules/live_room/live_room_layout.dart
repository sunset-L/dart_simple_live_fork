import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 系统独占旋转动画；页面仅按当前帧约束布局，视频与页内标签保持挂载。
class LiveRoomLayout extends StatefulWidget {
  final bool fullScreen;
  final bool landscapeFullScreen;
  final PreferredSizeWidget? appBar;
  final ValueChanged<bool>? onWindowLandscapeChanged;
  final Widget player;
  final Widget sidebar;
  final Widget portraitActions;

  const LiveRoomLayout({
    required this.fullScreen,
    this.landscapeFullScreen = true,
    this.appBar,
    this.onWindowLandscapeChanged,
    required this.player,
    required this.sidebar,
    required this.portraitActions,
    super.key,
  });

  @override
  State<LiveRoomLayout> createState() => _LiveRoomLayoutState();
}

class _LiveRoomLayoutState extends State<LiveRoomLayout> {
  bool? _lastWindowLandscape;

  @override
  Widget build(BuildContext context) {
    // MediaQuery 与本帧布局使用同一份尺寸，不混入实时变化的 physicalSize。
    final media = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final windowLandscape = media.orientation == Orientation.landscape;
      final layoutLandscape = constraints.maxWidth > constraints.maxHeight;
      // 键盘只压缩内容高度，不代表窗口横屏。方向与约束一致后才完成交接。
      if ((windowLandscape == layoutLandscape || media.viewInsets.bottom > 0) &&
          _lastWindowLandscape != windowLandscape) {
        _lastWindowLandscape = windowLandscape;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _lastWindowLandscape == windowLandscape) {
            widget.onWindowLandscapeChanged?.call(windowLandscape);
          }
        });
      }
      // 点击横屏全屏但窗口仍竖屏时，继续显示竖屏页；退出时反之。
      // 不能让全屏请求提前把旧方向的页面放进新方向的播放器约束。
      final fullScreen = windowLandscape && layoutLandscape ||
          widget.fullScreen && !widget.landscapeFullScreen;

      Widget pageContent(Widget child) => Offstage(
            offstage: fullScreen,
            child: TickerMode(
              enabled: !fullScreen,
              child: ExcludeFocus(
                excluding: fullScreen,
                child: child,
              ),
            ),
          );

      return ColoredBox(
        color: fullScreen
            ? Colors.black
            : Theme.of(context).scaffoldBackgroundColor,
        child: ClipRect(
          child: CustomMultiChildLayout(
            delegate: _LiveRoomLayoutDelegate(
              fullScreen: fullScreen,
              headerHeight: widget.appBar == null
                  ? 0
                  : widget.appBar!.preferredSize.height + media.padding.top,
            ),
            children: [
              if (widget.appBar != null)
                LayoutId(
                  id: _RoomPart.header,
                  child: pageContent(widget.appBar!),
                ),
              LayoutId(
                id: _RoomPart.actions,
                child: pageContent(widget.portraitActions),
              ),
              LayoutId(
                id: _RoomPart.sidebar,
                child: pageContent(widget.sidebar),
              ),
              LayoutId(
                id: _RoomPart.player,
                child: ClipRect(child: widget.player),
              ),
            ],
          ),
        ),
      );
    });
  }
}

enum _RoomPart { header, actions, sidebar, player }

class _LiveRoomLayoutDelegate extends MultiChildLayoutDelegate {
  final bool fullScreen;
  final double headerHeight;

  _LiveRoomLayoutDelegate({
    required this.fullScreen,
    required this.headerHeight,
  });

  @override
  void performLayout(Size size) {
    if (fullScreen) {
      // 隐藏子树只保留状态，不再用缓存的竖屏尺寸参与横屏布局。
      for (final part in [
        _RoomPart.header,
        _RoomPart.actions,
        _RoomPart.sidebar
      ]) {
        if (hasChild(part)) {
          layoutChild(part, BoxConstraints.loose(size));
          positionChild(part, Offset.zero);
        }
      }
      layoutChild(_RoomPart.player, BoxConstraints.tight(size));
      positionChild(_RoomPart.player, Offset.zero);
      return;
    }
    final header = math.min(headerHeight, size.height);
    if (hasChild(_RoomPart.header)) {
      layoutChild(
        _RoomPart.header,
        BoxConstraints.tight(Size(size.width, header)),
      );
      positionChild(_RoomPart.header, Offset.zero);
    }
    final actions = layoutChild(
      _RoomPart.actions,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: math.max(0.0, size.height - header),
      ),
    );
    positionChild(_RoomPart.actions, Offset(0, size.height - actions.height));
    final bodyHeight = math.max(0.0, size.height - header - actions.height);
    final playerHeight = math.min(size.width * 9 / 16, bodyHeight);
    layoutChild(
      _RoomPart.sidebar,
      BoxConstraints.tight(Size(size.width, bodyHeight - playerHeight)),
    );
    positionChild(_RoomPart.sidebar, Offset(0, header + playerHeight));
    final playerRect = Rect.fromLTWH(0, header, size.width, playerHeight);
    layoutChild(_RoomPart.player, BoxConstraints.tight(playerRect.size));
    positionChild(_RoomPart.player, playerRect.topLeft);
  }

  @override
  bool shouldRelayout(covariant _LiveRoomLayoutDelegate oldDelegate) =>
      fullScreen != oldDelegate.fullScreen ||
      headerHeight != oldDelegate.headerHeight;
}
