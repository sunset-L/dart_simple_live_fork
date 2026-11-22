import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 系统负责旋转，Flutter 只在方向不变时插值播放器尺寸。
class LiveRoomLayout extends StatefulWidget {
  final bool fullScreen;
  final bool landscapeFullScreen;
  final bool systemFullScreen;
  final PreferredSizeWidget? appBar;
  final VoidCallback? onInlineRestored;
  final ValueChanged<bool>? onWindowLandscapeChanged;
  final Widget player;
  final Widget sidebar;
  final Widget portraitActions;

  const LiveRoomLayout({
    required this.fullScreen,
    this.landscapeFullScreen = true,
    this.systemFullScreen = false,
    this.appBar,
    this.onInlineRestored,
    this.onWindowLandscapeChanged,
    required this.player,
    required this.sidebar,
    required this.portraitActions,
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
  bool? _lastWindowLandscape;

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
      _rotatesWindow = _landscapeFullScreen;
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
        // MediaQuery 可能仍属于上一次窗口帧；旋转交接使用同一 FlutterView 的
        // 实际尺寸。键盘只改变 inset，不改变 physicalSize，不能误判为横屏。
        final windowSize = View.of(context).physicalSize;
        final windowLandscape = windowSize.width > windowSize.height;
        if (_lastWindowLandscape != windowLandscape) {
          _lastWindowLandscape = windowLandscape;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _lastWindowLandscape == windowLandscape) {
              widget.onWindowLandscapeChanged?.call(windowLandscape);
            }
          });
        }
        // 键盘缩高不能触发横屏；方向和实际约束都恢复后才展示竖屏内容。
        final landscape = windowLandscape && size.width > size.height;
        if (_waitingForInlineOrientation &&
            !windowLandscape &&
            size.width <= size.height) {
          _waitingForInlineOrientation = false;
          _orientationTimeout?.cancel();
          _inlineSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !widget.fullScreen) _transition.reverse();
          });
        }
        if (!widget.fullScreen &&
            !windowLandscape &&
            !_waitingForInlineOrientation &&
            _transition.isDismissed) {
          _inlineSize = size;
          _inlineMedia = media;
        }
        final inlineWidth =
            windowLandscape ? math.min(size.width, size.height) : size.width;
        final inlineSize = _inlineSize ??= Size(
          inlineWidth,
          math.max(
            windowLandscape ? size.width : size.height,
            inlineWidth * 9 / 16 + 400,
          ),
        );
        final inlineMedia = _inlineMedia ??= media.copyWith(size: inlineSize);

        return AnimatedBuilder(
          animation: _transition,
          builder: (context, _) {
            final progress = Curves.easeInOutCubic.transform(_transition.value);
            // 退出旋转时播放器已缩回，页面内容须在同一帧出现，不能再露出黑底。
            final contentProgress = windowLandscape
                ? 1.0
                : widget.systemFullScreen ||
                        _rotatesWindow &&
                            !widget.fullScreen &&
                            !_waitingForInlineOrientation
                    ? 0.0
                    : progress;
            final hidden = _waitingForInlineOrientation || contentProgress == 1;
            final inactive =
                windowLandscape || widget.fullScreen || progress > 0;
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
                    headerHeight: widget.appBar == null
                        ? 0
                        : widget.appBar!.preferredSize.height +
                            inlineMedia.padding.top,
                    progress: progress,
                    rotatesWindow: _rotatesWindow,
                    fullScreen: widget.fullScreen,
                    targetOrientationReached: landscape == _landscapeFullScreen,
                    waitingForOrientation: _waitingForInlineOrientation,
                    windowLandscape: windowLandscape,
                    systemFullScreen: widget.systemFullScreen,
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
  final double headerHeight;
  final double progress;
  final bool rotatesWindow;
  final bool fullScreen;
  final bool targetOrientationReached;
  final bool waitingForOrientation;
  final bool windowLandscape;
  final bool systemFullScreen;

  _LiveRoomLayoutDelegate({
    required this.inlineSize,
    required this.headerHeight,
    required this.progress,
    required this.rotatesWindow,
    required this.fullScreen,
    required this.targetOrientationReached,
    required this.waitingForOrientation,
    required this.windowLandscape,
    required this.systemFullScreen,
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
    final playerWidth = inlineSize.width;
    final playerHeight = math.min(playerWidth * 9 / 16, bodyHeight);
    layoutChild(
      _RoomPart.sidebar,
      BoxConstraints.tight(Size(
        inlineSize.width,
        math.max(0.0, bodyHeight - playerHeight),
      )),
    );
    positionChild(
      _RoomPart.sidebar,
      Offset(0, headerHeight + playerHeight),
    );

    final inlineRect =
        Rect.fromLTWH(0, headerHeight, playerWidth, playerHeight);
    final fullRect = Offset.zero & size;
    // 系统旋转已在合成新旧窗口帧，不能再插值出比例不同的播放器中间帧。
    final Rect playerRect;
    if (windowLandscape) {
      playerRect = fullRect;
    } else if (systemFullScreen) {
      playerRect = inlineRect;
    } else if (rotatesWindow) {
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
      headerHeight != oldDelegate.headerHeight ||
      progress != oldDelegate.progress ||
      rotatesWindow != oldDelegate.rotatesWindow ||
      fullScreen != oldDelegate.fullScreen ||
      targetOrientationReached != oldDelegate.targetOrientationReached ||
      waitingForOrientation != oldDelegate.waitingForOrientation ||
      windowLandscape != oldDelegate.windowLandscape ||
      systemFullScreen != oldDelegate.systemFullScreen;
}
