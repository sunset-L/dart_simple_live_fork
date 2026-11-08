import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/utils.dart';

class PlayerRoomTitle extends StatelessWidget {
  final String? title;
  final int online;

  const PlayerRoomTitle({
    super.key,
    required this.title,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title ?? '正在读取直播信息...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppStyle.textStyleWhite,
          ),
        ),
        if (title != null) ...[
          SizedBox(width: 16.w),
          Semantics(
            label: '热度 ${Utils.onlineToString(online)}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.whatshot, color: Colors.white70, size: 24.w),
                SizedBox(width: 8.w),
                Text(
                  Utils.onlineToString(online),
                  style: AppStyle.textStyleWhite.copyWith(
                    color: Colors.white70,
                    fontSize: 24.w,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
