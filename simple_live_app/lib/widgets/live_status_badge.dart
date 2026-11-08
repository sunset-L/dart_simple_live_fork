import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';

class LiveStatusBadge extends StatelessWidget {
  /// 0=未知（加载中），1=未开播，2=直播中。
  final int status;

  const LiveStatusBadge({required this.status, super.key});

  static String getStatus(int status) {
    if (status == 0) {
      return "读取中";
    } else if (status == 1) {
      return "未开播";
    } else {
      return "直播中";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: status == 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppStyle.hGap12,
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status == 2 ? Colors.green : Colors.grey,
              borderRadius: AppStyle.radius12,
            ),
          ),
          AppStyle.hGap4,
          Text(
            getStatus(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: status == 2 ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
