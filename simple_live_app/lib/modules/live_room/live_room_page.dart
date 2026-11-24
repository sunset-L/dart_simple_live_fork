import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 仅保留业务路由生命周期；播放页所有可见 UI 都由 Android View 渲染。
/// 不创建视频纹理、PlatformView、聊天列表或 Flutter 播放控件。
class LiveRoomPage extends GetView<LiveRoomController> {
  const LiveRoomPage({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) await controller.handleBackPressed();
        },
        child: const ColoredBox(color: Colors.black),
      );
}
