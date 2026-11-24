import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 竖屏业务页及大屏布局；全屏旋转由 Android 原生页面负责。
class LiveRoomLayout extends StatelessWidget {
  final bool fullScreen;
  final bool landscapeFullScreen;
  final PreferredSizeWidget? appBar;
  final Widget player;
  final Widget sidebar;
  final Widget portraitActions;

  const LiveRoomLayout({
    required this.fullScreen,
    this.landscapeFullScreen = true,
    this.appBar,
    required this.player,
    required this.sidebar,
    required this.portraitActions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // MediaQuery 与本帧布局使用同一份尺寸，不混入实时变化的 physicalSize。
    final media = MediaQuery.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final windowLandscape = media.orientation == Orientation.landscape;
      final layoutLandscape = constraints.maxWidth > constraints.maxHeight;
      // 约束决定实际布局；键盘压缩内容高度不代表横屏。
      final expandedPlayer = layoutLandscape &&
              (windowLandscape || media.viewInsets.bottom == 0) ||
          fullScreen && !landscapeFullScreen;

      Widget pageContent(Widget child) => Offstage(
            offstage: expandedPlayer,
            child: TickerMode(
              enabled: !expandedPlayer,
              child: ExcludeFocus(
                excluding: expandedPlayer,
                child: child,
              ),
            ),
          );

      return ColoredBox(
        color: expandedPlayer
            ? Colors.black
            : Theme.of(context).scaffoldBackgroundColor,
        child: ClipRect(
          child: CustomMultiChildLayout(
            delegate: _LiveRoomLayoutDelegate(
              fullScreen: expandedPlayer,
              headerHeight: appBar == null
                  ? 0
                  : appBar!.preferredSize.height + media.padding.top,
            ),
            children: [
              if (appBar != null)
                LayoutId(
                  id: _RoomPart.header,
                  child: pageContent(appBar!),
                ),
              LayoutId(
                id: _RoomPart.actions,
                child: pageContent(portraitActions),
              ),
              LayoutId(
                id: _RoomPart.sidebar,
                child: pageContent(sidebar),
              ),
              LayoutId(
                id: _RoomPart.player,
                child: ClipRect(child: player),
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
