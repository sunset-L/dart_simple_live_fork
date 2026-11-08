import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/db_service.dart';

class HistoryController extends BasePageController<History> {
  StreamSubscription<dynamic>? _historySubscription;
  Timer? _refreshTimer;

  @override
  void onInit() {
    // 标签页会留在关注页中，观看直播、同步或删除后及时刷新本地记录。
    _historySubscription = DBService.instance.historyBox.watch().listen((_) {
      _refreshTimer ??= Timer(Duration.zero, () {
        _refreshTimer = null;
        if (!isClosed) refreshData();
      });
    });
    refreshData();
    super.onInit();
  }

  @override
  Future<void> refreshData() async {
    if (isClosed) return;
    // 记录一次读取完整，直接替换快照，避免常驻标签页刷新时先清空闪动。
    try {
      list.assignAll(DBService.instance.getHistores());
      currentPage = 2;
      canLoadMore.value = false;
      pageEmpty.value = list.isEmpty;
      pageError.value = false;
    } catch (e) {
      pageEmpty.value = false;
      handleError(e, showPageError: true);
    } finally {
      pageLoadding.value = false;
    }
  }

  @override
  Future<List<History>> getData(int page, int pageSize) {
    if (page > 1) {
      return Future.value([]);
    }
    return Future.value(DBService.instance.getHistores());
  }

  void clean() async {
    var result = await Utils.showAlertDialog("确定要清空观看记录吗?", title: "清空观看记录");
    if (!result || isClosed) {
      return;
    }
    await DBService.instance.historyBox.clear();
    refreshData();
  }

  void removeItem(History item) async {
    await DBService.instance.historyBox.delete(item.id);
    refreshData();
  }

  @override
  void onClose() {
    _historySubscription?.cancel();
    _refreshTimer?.cancel();
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }
}
