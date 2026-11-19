import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 系统负责旋转，Flutter 只在方向不变时插值播放器尺寸。
class LiveRoomLayout extends StatefulWidget {
  final bool fullScreen;
  final bool landscapeFullScreen;
  final PreferredSizeWidget? appBar;
  final VoidCallback? onInlineRestored;
  final Widget player;
  final Widget sidebar;
  final Widget portraitActions;
  final Widget landscapeActions;

  const LiveRoomLayout({
    required this.fullScreen,
    this.landscapeFullScreen = true,
    this.appBar,
    this.onInlineRestored,
    required this.player,
    required this.sidebar,
    required this.portraitActions,
    required this.landscapeActions,
    super.key,
  });

  @override
  State<LiveRoomLayout> createState() => _LiveRoomLayoutState();
}

class _LiveRoomLayoutState extends State<LiveRoomLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition;
  Size? _inlineSize;
  MediaQueryData? _inlineMedia;
  bool _landscapeFullScreen = true;
  bool _rotatesWindow = false;
  bool _waitingForInlineOrientation = false;
  Timer? _orientationTimeout;

  @override
  void initState() {
    super.initState();
    _landscapeFullScreen = widget.landscapeFullScreen;
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.fullScreen ? 1 : 0,
    )..addStatusListener(_onAnimationStatus);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.fullScreen) {
      widget.onInlineRestored?.call();
    }
  }

  @override
  void didUpdateWidget(covariant LiveRoomLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullScreen &&
        (!oldWidget.fullScreen ||
            oldWidget.landscapeFullScreen != widget.landscapeFullScreen)) {
      _landscapeFullScreen = widget.landscapeFullScreen;
      _rotatesWindow = _inlineMedia != null &&
          (_inlineMedia!.orientation == Orientation.landscape) !=
              _landscapeFullScreen;
    }
    if (oldWidget.fullScreen == widget.fullScreen) return;
    _orientationTimeout?.cancel();
    if (widget.fullScreen) {
      _waitingForInlineOrientation = false;
      _transition.forward();
    } else {
      // 系统仍是横向窗口时，不能先把播放器塞回竖屏半屏约束。
      _waitingForInlineOrientation = true;
      _orientationTimeout = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted || !_waitingForInlineOrientation) return;
        setState(() {
          // 系统拒绝旋转时按实际窗口恢复，不能永久隐藏聊天和操作。
          _inlineSize = null;
          _inlineMedia = null;
          _waitingForInlineOrientation = false;
        });
        _transition.reverse();
      });
    }
  }

  @override
  void dispose() {
    _orientationTimeout?.cancel();
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 方向交接以实际约束为准；普通布局保留窗口方向，不能把键盘缩高当成横屏。
        final landscape = size.width > size.height;
        if (_waitingForInlineOrientation &&
            (_inlineMedia == null ||
                landscape ==
                    (_inlineMedia!.orientation == Orientation.landscape))) {
          _waitingForInlineOrientation = false;
          _orientationTimeout?.cancel();
          _inlineSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !widget.fullScreen) _transition.reverse();
          });
        }
        if (!widget.fullScreen &&
            !_waitingForInlineOrientation &&
            _transition.isDismissed) {
          _inlineSize = size;
          _inlineMedia = media;
        }
        final inlineMedia = _inlineMedia ??= media;
        final portrait = inlineMedia.orientation == Orientation.portrait;
        final inlineSize = _inlineSize ??= Size(
          size.width,
          math.max(size.height, (portrait ? size.width * 9 / 16 : 0) + 400),
        );

        return AnimatedBuilder(
          animation: _transition,
          builder: (context, _) {
            final progress = Curves.easeInOutCubic.transform(_transition.value);
            // 退出旋转时播放器已缩回，页面内容须在同一帧出现，不能再露出黑底。
            final contentProgress = _rotatesWindow &&
                    !widget.fullScreen &&
                    !_waitingForInlineOrientation
                ? 0.0
                : progress;
            final hidden = _waitingForInlineOrientation || contentProgress == 1;
            final inactive = widget.fullScreen || progress > 0;
            final opacity = 1 - contentProgress;

            Widget pageContent(Widget child) => MediaQuery(
                  data: inlineMedia,
                  child: Visibility(
                    visible: !hidden,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: TickerMode(
                      enabled: !hidden,
                      child: ExcludeFocus(
                        excluding: inactive,
                        child: IgnorePointer(
                          ignoring: inactive,
                          child: Opacity(opacity: opacity, child: child),
                        ),
                      ),
                    ),
                  ),
                );

            return ColoredBox(
              color: Color.lerp(
                Theme.of(context).scaffoldBackgroundColor,
                Colors.black,
                contentProgress,
              )!,
              child: ClipRect(
                child: CustomMultiChildLayout(
                  delegate: _LiveRoomLayoutDelegate(
                    inlineSize: inlineSize,
                    portrait: portrait,
                    headerHeight: widget.appBar == null
                        ? 0
                        : widget.appBar!.preferredSize.height +
                            inlineMedia.padding.top,
                    progress: progress,
                    rotatesWindow: _rotatesWindow,
                    fullScreen: widget.fullScreen,
                    targetOrientationReached: landscape == _landscapeFullScreen,
                    waitingForOrientation: _waitingForInlineOrientation,
                  ),
                  children: [
                    if (widget.appBar != null)
                      LayoutId(
                        id: _RoomPart.header,
                        child: pageContent(widget.appBar!),
                      ),
                    LayoutId(
                      id: _RoomPart.actions,
                      child: pageContent(portrait
                          ? widget.portraitActions
                          : widget.landscapeActions),
                    ),
                    LayoutId(
                      id: _RoomPart.sidebar,
                      child: pageContent(widget.sidebar),
                    ),
                    LayoutId(
                      id: _RoomPart.player,
                      // 工具栏滑出时裁在播放器内，不能盖到下方资料区。
                      child: ClipRect(child: widget.player),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _RoomPart { header, actions, sidebar, player }

class _LiveRoomLayoutDelegate extends MultiChildLayoutDelegate {
  final Size inlineSize;
  final bool portrait;
  final double headerHeight;
  final double progress;
  final bool rotatesWindow;
  final bool fullScreen;
  final bool targetOrientationReached;
  final bool waitingForOrientation;

  _LiveRoomLayoutDelegate({
    required this.inlineSize,
    required this.portrait,
    required this.headerHeight,
    required this.progress,
    required this.rotatesWindow,
    required this.fullScreen,
    required this.targetOrientationReached,
    required this.waitingForOrientation,
  });

  @override
  void performLayout(Size size) {
    if (hasChild(_RoomPart.header)) {
      layoutChild(
        _RoomPart.header,
        BoxConstraints.tight(Size(inlineSize.width, headerHeight)),
      );
      positionChild(_RoomPart.header, Offset.zero);
    }
    final actionsSize = layoutChild(
      _RoomPart.actions,
      BoxConstraints(
        minWidth: inlineSize.width,
        maxWidth: inlineSize.width,
        maxHeight: inlineSize.height,
      ),
    );
    positionChild(
      _RoomPart.actions,
      Offset(0, inlineSize.height - actionsSize.height),
    );
    final bodyHeight =
        math.max(0.0, inlineSize.height - headerHeight - actionsSize.height);
    final sidebarWidth =
        portrait ? inlineSize.width : math.min(300.0, inlineSize.width / 2);
    final playerWidth =
        portrait ? inlineSize.width : inlineSize.width - sidebarWidth;
    final playerHeight =
        portrait ? math.min(playerWidth * 9 / 16, bodyHeight) : bodyHeight;
    layoutChild(
      _RoomPart.sidebar,
      BoxConstraints.tight(Size(
        sidebarWidth,
        portrait ? math.max(0.0, bodyHeight - playerHeight) : bodyHeight,
      )),
    );
    positionChild(
      _RoomPart.sidebar,
      Offset(portrait ? 0 : playerWidth,
          headerHeight + (portrait ? playerHeight : 0)),
    );

    final inlineRect =
        Rect.fromLTWH(0, headerHeight, playerWidth, playerHeight);
    final fullRect = Offset.zero & size;
    // 系统旋转已在合成新旧窗口帧，不能再插值出比例不同的播放器中间帧。
    final Rect playerRect;
    if (rotatesWindow) {
      playerRect = (fullScreen && targetOrientationReached) ||
              (!fullScreen && waitingForOrientation)
          ? fullRect
          : inlineRect;
    } else {
      playerRect = waitingForOrientation
          ? fullRect
          : Rect.lerp(inlineRect, fullRect, progress)!;
    }
    layoutChild(_RoomPart.player, BoxConstraints.tight(playerRect.size));
    positionChild(_RoomPart.player, playerRect.topLeft);
  }

  @override
  bool shouldRelayout(covariant _LiveRoomLayoutDelegate oldDelegate) =>
      inlineSize != oldDelegate.inlineSize ||
      portrait != oldDelegate.portrait ||
      headerHeight != oldDelegate.headerHeight ||
      progress != oldDelegate.progress ||
      rotatesWindow != oldDelegate.rotatesWindow ||
      fullScreen != oldDelegate.fullScreen ||
      targetOrientationReached != oldDelegate.targetOrientationReached ||
      waitingForOrientation != oldDelegate.waitingForOrientation;
}
