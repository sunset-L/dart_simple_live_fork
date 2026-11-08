import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 固定播放器、资料聊天区的挂载位置，切换全屏只改变布局约束。
class LiveRoomLayout extends StatefulWidget {
  final bool fullScreen;
  final Widget player;
  final Widget sidebar;
  final Widget portraitActions;
  final Widget landscapeActions;

  const LiveRoomLayout({
    required this.fullScreen,
    required this.player,
    required this.sidebar,
    required this.portraitActions,
    required this.landscapeActions,
    super.key,
  });

  @override
  State<LiveRoomLayout> createState() => _LiveRoomLayoutState();
}

class _LiveRoomLayoutState extends State<LiveRoomLayout> {
  Size? _inlineSize;
  Orientation? _inlineOrientation;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              if (!widget.fullScreen) {
                _inlineSize = size;
                _inlineOrientation = orientation;
              }
              final inlineOrientation = _inlineOrientation ?? orientation;
              final portrait = inlineOrientation == Orientation.portrait;
              // 全屏旋转期间沿用半屏约束，隐藏的聊天区不会被挤压重排。
              // 自动全屏首次进入时，也给隐藏的资料区保留足够高度。
              final inlineSize = _inlineSize ??
                  Size(
                    size.width,
                    math.max(
                      size.height,
                      (portrait ? size.width * 9 / 16 : 0) + 320,
                    ),
                  );
              final sidebarWidth = portrait
                  ? inlineSize.width
                  : math.min(300.0, inlineSize.width);
              final playerWidth =
                  portrait ? inlineSize.width : inlineSize.width - sidebarWidth;
              final playerHeight =
                  portrait ? inlineSize.width * 9 / 16 : inlineSize.height;
              final sidebarTop = portrait ? playerHeight : 0.0;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: widget.fullScreen ? size.width : playerWidth,
                    height: widget.fullScreen ? size.height : playerHeight,
                    child: widget.player,
                  ),
                  Positioned(
                    left: portrait ? 0 : playerWidth,
                    top: sidebarTop,
                    width: sidebarWidth,
                    height: math.max(0.0, inlineSize.height - sidebarTop),
                    child: Offstage(
                      offstage: widget.fullScreen,
                      child: TickerMode(
                        enabled: !widget.fullScreen,
                        child: ExcludeFocus(
                          excluding: widget.fullScreen,
                          child: widget.sidebar,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Offstage(
          offstage: widget.fullScreen,
          child: TickerMode(
            enabled: !widget.fullScreen,
            child: ExcludeFocus(
              excluding: widget.fullScreen,
              child: orientation == Orientation.portrait
                  ? widget.portraitActions
                  : widget.landscapeActions,
            ),
          ),
        ),
      ],
    );
  }
}
