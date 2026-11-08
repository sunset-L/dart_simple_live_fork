// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser> {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 0:全部 1:直播中 2:未直播
  var filterMode = FollowUserTag(id: "0", tag: "全部", userId: []).obs;
  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "直播中", userId: []),
    FollowUserTag(id: "2", tag: "未开播", userId: []),
  ].obs;

  // 用户自定义标签
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  final PageController tagPageController = PageController(keepPage: false);
  final tagUsers = <String, List<FollowUser>>{}.obs;
  final Map<String, VoidCallback> _tagScrollActions = {};
  String? _targetTagId;
  int _pageTransition = 0;

  int get selectedTagIndex =>
      tagList.indexWhere((tag) => tag.id == filterMode.value.id);

  @override
  void onInit() {
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream =
        FollowService.instance.updatedListStream.listen((event) {
      filterData();
    });
    updateTagList();
    super.onInit();
  }

  @override
  void onReady() {
    super.onReady();
    if (!isClosed) {
      refreshData();
    }
  }

  @override
  Future refreshData() async {
    await FollowService.instance.loadData();
    updateTagList();
    await super.refreshData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    if (page > 1) {
      return Future.value([]);
    }
    if (filterMode.value.tag == "全部") {
      return FollowService.instance.followList.value;
    } else if (filterMode.value.tag == "直播中") {
      return FollowService.instance.liveList.value;
    } else if (filterMode.value.tag == "未开播") {
      return FollowService.instance.notLiveList.value;
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      return FollowService.instance.curTagFollowList.value;
    }
  }

  void updateTagList() {
    userTagList.assignAll(FollowService.instance.followTagList);
    tagList.assignAll([...tagList.take(3), ...userTagList]);
    // 刷新、改名后按 ID 保持选中；当前标签被删除时回到“全部”。
    filterMode.value = tagList.firstWhere(
      (tag) => tag.id == filterMode.value.id,
      orElse: () => tagList.first,
    );
    filterData();
    _alignTagPage();
  }

  void filterData() {
    final service = FollowService.instance;
    final usersById = {for (final user in service.followList) user.id: user};
    final pages = <String, List<FollowUser>>{
      '0': service.followList.toList(),
      '1': service.liveList.toList(),
      '2': service.notLiveList.toList(),
    };
    // 各页读取独立快照，拖动过程中相邻页能同时显示正确的筛选结果。
    for (final tag in userTagList) {
      final users = tag.userId
          .map((id) => usersById[id])
          .whereType<FollowUser>()
          .toList();
      users.sort((a, b) => b.liveStatus.value.compareTo(a.liveStatus.value));
      pages[tag.id] = users;
    }
    tagUsers.value = pages;
    _updateSelectedList();
  }

  List<FollowUser> usersForTag(FollowUserTag tag) => tagUsers[tag.id] ?? [];

  void _updateSelectedList() {
    list.assignAll(usersForTag(filterMode.value));
    pageEmpty.value = list.isEmpty;
    if (selectedTagIndex >= 3) {
      FollowService.instance.curTagFollowList.assignAll(list);
    }
  }

  void setFilterMode(FollowUserTag tag) {
    filterMode.value = tag;
    _updateSelectedList();
    if (!tagPageController.hasClients || selectedTagIndex < 0) {
      return;
    }
    final transition = ++_pageTransition;
    _targetTagId = tag.id;
    tagPageController
        .animateToPage(
      selectedTagIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    )
        .whenComplete(() {
      if (isClosed || transition != _pageTransition) {
        return;
      }
      _targetTagId = null;
      if (tagPageController.hasClients) {
        onTagPageChanged(tagPageController.page!.round());
      }
    });
  }

  void onTagPageChanged(int index) {
    if (index < 0 || index >= tagList.length) {
      return;
    }
    final tag = tagList[index];
    // 点击远处标签时，动画路过的中间页不改变目标标签的高亮。
    if (_targetTagId != null && _targetTagId != tag.id) {
      return;
    }
    filterMode.value = tag;
    _updateSelectedList();
  }

  void onTagDragStarted() {
    _pageTransition++;
    _targetTagId = null;
    if (tagPageController.hasClients) {
      onTagPageChanged(tagPageController.page!.round());
    }
  }

  void _alignTagPage() {
    final transition = ++_pageTransition;
    _targetTagId = filterMode.value.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || transition != _pageTransition) {
        return;
      }
      if (tagPageController.hasClients && selectedTagIndex >= 0) {
        tagPageController.jumpToPage(selectedTagIndex);
      }
      _targetTagId = null;
    });
  }

  void registerTagScrollAction(String tagId, VoidCallback action) {
    _tagScrollActions[tagId] = action;
  }

  void unregisterTagScrollAction(String tagId) {
    _tagScrollActions.remove(tagId);
  }

  @override
  void scrollToTopOrRefresh() {
    final action = _tagScrollActions[filterMode.value.id];
    if (action != null) {
      action();
    } else {
      refreshData();
    }
  }

  void switchTag(int offset) {
    final currentIndex =
        tagList.indexWhere((tag) => tag.id == filterMode.value.id);
    final nextIndex = (currentIndex < 0 ? 0 : currentIndex) + offset;
    if (nextIndex < 0 || nextIndex >= tagList.length) {
      return;
    }
    setFilterMode(tagList[nextIndex]);
  }

  void removeItem(FollowUser item) async {
    var result =
        await Utils.showAlertDialog("确定要取消关注${item.userName}吗?", title: "取消关注");
    if (!result) {
      return;
    }
    // 取消关注同时删除标签内的 userId
    if (item.tag != "全部") {
      var tag = tagList.firstWhere((tag) => tag.tag == item.tag);
      tag.userId.remove(item.id);
      updateTag(tag);
    }
    await DBService.instance.followBox.delete(item.id);
    refreshData();
  }

  void updateItem(FollowUser item) {
    FollowService.instance.addFollow(item);
  }

  // 修改item的标签
  void setItemTag(FollowUser item, FollowUserTag targetTag) {
    FollowUserTag tarTag = targetTag;
    FollowUserTag curTag = tagList.firstWhere((tag) => tag.tag == item.tag);
    // 从当前标签（非全部）删除item 向目标标签(全部包含所有item == 非全部)添加item
    curTag.userId.remove(item.id);
    tarTag.userId.addIf(!tarTag.userId.contains(item.id), item.id);
    // 数据库更新
    item.tag = tarTag.tag;
    updateTag(curTag);
    updateTag(tarTag);
    updateItem(item);
    filterData();
  }

  Future<void> removeTag(FollowUserTag tag) async {
    // 将tag下的所有follow设置为全部
    for (var i in tag.userId) {
      var follow = DBService.instance.followBox.get(i);
      if (follow != null) {
        follow.tag = "全部";
        updateItem(follow);
      }
    }
    await FollowService.instance.delFollowUserTag(tag);
    updateTagList();
    Log.i('删除tag${tag.tag}');
  }

  void addTag(String tag) async {
    FollowService.instance
        .addFollowUserTag(tag)
        .then((value) => updateTagList());
  }

  void updateTag(FollowUserTag followUserTag) {
    if (followUserTag.tag == '全部') {
      return;
    }
    FollowService.instance.updateFollowUserTag(followUserTag);
  }

  void updateTagName(FollowUserTag followUserTag, String newTagName) {
    // 未操作
    if (followUserTag.tag == newTagName) {
      return;
    }
    // 避免重名
    if (tagList.any((item) => item.tag == newTagName)) {
      SmartDialog.showToast("标签名重复，修改失败");
      return;
    }
    final FollowUserTag newTag = followUserTag.copyWith(tag: newTagName);
    updateTag(newTag);
    // update item's tag when update tagName
    for (var i in newTag.userId) {
      var follow = DBService.instance.followBox.get(i);
      if (follow != null) {
        follow.tag = newTagName;
        updateItem(follow);
      }
    }
    SmartDialog.showToast("标签名修改成功");
    updateTagList();
  }

  // 调整标签顺序
  void updateTagOrder(int oldIndex, int newIndex) {
    final item = userTagList.removeAt(oldIndex);
    userTagList.insert(newIndex, item);
    tagList.assignAll([...tagList.take(3), ...userTagList]);
    _alignTagPage();
    DBService.instance.updateFollowTagOrder(userTagList);
  }

  @override
  void onClose() {
    onUpdatedIndexedStream?.cancel();
    onUpdatedListStream?.cancel();
    _tagScrollActions.clear();
    tagPageController.dispose();
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }
}
