import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// 未开播和加载失败共用的播放器内状态提示。
class LiveRoomStatusOverlay extends StatelessWidget {
  final String userName;
  final String userAvatar;
  final String title;
  final String? description;
  final VoidCallback onRefresh;
  final VoidCallback? onCopyError;
  final VoidCallback? onExitFullScreen;

  const LiveRoomStatusOverlay({
    required this.userName,
    required this.userAvatar,
    required this.title,
    required this.onRefresh,
    this.description,
    this.onCopyError,
    this.onExitFullScreen,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (userAvatar.isNotEmpty) ...[
                    NetImage(
                      userAvatar,
                      width: 48,
                      height: 48,
                      borderRadius: 24,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    userName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Remix.refresh_line, size: 16),
                        label: const Text('刷新'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (onCopyError != null)
                        IconButton(
                          onPressed: onCopyError,
                          tooltip: '复制错误信息',
                          icon: const Icon(Remix.file_copy_line, size: 18),
                          color: Colors.white54,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onExitFullScreen != null)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: onExitFullScreen,
                tooltip: '退出全屏',
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
