import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';

Future<({bool isLiving, String? startTime})> fetchFollowLiveStatus(
  LiveSite site,
  String roomId,
) async {
  if (site is DouyinSite) {
    final detail = await site.getRoomDetail(roomId: roomId);
    return (
      isLiving: detail.status,
      startTime: detail.status ? detail.showTime : null,
    );
  }

  final isLiving = await site.getLiveStatus(roomId: roomId);
  if (!isLiving) return (isLiving: false, startTime: null);

  String? startTime;
  try {
    if (site is DouyuSite) {
      startTime = await site.getLiveStartTime(roomId: roomId);
    } else if (site is BiliBiliSite) {
      final info = await site.getRoomInfo(roomId: roomId);
      startTime = info['room_info']?['live_start_time']?.toString();
    } else if (site is! HuyaSite) {
      startTime = (await site.getRoomDetail(roomId: roomId)).showTime;
    }
  } catch (error) {
    Log.logPrint(error);
  }
  return (isLiving: true, startTime: startTime);
}
