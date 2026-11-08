import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Form;
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 直播间加载失败的原因分类
///
/// 为什么需要分类：原来的实现是把 [error] 的 `toString()` 直接显示在页面上，
/// 用户经常看到的是 `type 'Null' is not a subtype of type 'String'`
/// 这类内部异常。它既解释不了「为什么打不开」，也提示不了「该做什么」——
/// 主播被封禁和网络断了在页面上长得一模一样。
///
/// 分类的目标只有一个：给出一句用户能理解的原因 + 一个明确的下一步动作。
enum LiveRoomErrorKind {
  /// 房间不存在 / 房间号失效 / 主播注销（平台明确返回 404 等）
  notFound,

  /// 接口通了，但里面没有预期的房间数据
  ///
  /// 抖音主播被封禁、直播间被关闭时最常见：接口仍返回 200，
  /// 但 `data.room` 为空，取字段时抛类型错误。
  dataMissing,

  /// 平台限制访问：风控、限流、Cookie 异常（401 / 403 / 412 / 418 / 429）
  blocked,

  /// 网络不通：DNS 失败、连接被重置
  network,

  /// 请求超时
  timeout,

  /// 平台服务端错误（5xx）
  server,

  /// 没归类成功
  unknown,

  /// 平台明确提示主播未开播 / 直播已结束
  notLive,
}

/// 分类后的展示信息
class LiveRoomErrorInfo {
  /// 原因分类
  final LiveRoomErrorKind kind;

  /// 主标题：一句话说清发生了什么
  final String title;

  /// 补充说明：可能的原因 / 建议动作
  final String tip;

  /// 主图标
  final IconData icon;

  /// 重试是否可能有意义
  ///
  /// 用于区分临时故障与房间状态；播放器内统一保留手动刷新入口。
  final bool retryable;

  const LiveRoomErrorInfo({
    required this.kind,
    required this.title,
    required this.tip,
    required this.icon,
    required this.retryable,
  });
}

/// 把任意异常翻译成可展示的原因
///
/// [siteName] 只用于文案（「抖音服务异常」），不传则用「直播平台」。
LiveRoomErrorInfo describeLiveRoomError(Object? error, {String? siteName}) {
  final kind = _classify(error);
  final platform = siteName ?? "直播平台";

  switch (kind) {
    case LiveRoomErrorKind.notFound:
      return LiveRoomErrorInfo(
        kind: kind,
        title: "直播间不存在",
        tip: "该房间号可能已失效，或主播已注销账号。",
        icon: Remix.emotion_sad_line,
        retryable: false,
      );
    case LiveRoomErrorKind.dataMissing:
      return LiveRoomErrorInfo(
        kind: kind,
        title: "直播间暂时无法打开",
        tip: "主播可能未开播、已被平台封禁，或该房间已关闭。",
        icon: Remix.vidicon_line,
        retryable: false,
      );
    case LiveRoomErrorKind.blocked:
      return LiveRoomErrorInfo(
        kind: kind,
        title: "访问被平台限制",
        tip: "$platform暂时拒绝了这次请求，通常是请求过于频繁或账号凭证异常。",
        icon: Remix.forbid_line,
        retryable: true,
      );
    case LiveRoomErrorKind.network:
      return const LiveRoomErrorInfo(
        kind: LiveRoomErrorKind.network,
        title: "网络连接失败",
        tip: "请检查网络连接后重试。",
        icon: Remix.wifi_off_line,
        retryable: true,
      );
    case LiveRoomErrorKind.timeout:
      return const LiveRoomErrorInfo(
        kind: LiveRoomErrorKind.timeout,
        title: "加载超时",
        tip: "直播平台响应太慢，请稍后重试。",
        icon: Remix.time_line,
        retryable: true,
      );
    case LiveRoomErrorKind.server:
      return LiveRoomErrorInfo(
        kind: kind,
        title: "$platform服务异常",
        tip: "平台服务暂时不可用，请稍后重试。",
        icon: Remix.cloud_off_line,
        retryable: true,
      );
    case LiveRoomErrorKind.notLive:
      return const LiveRoomErrorInfo(
        kind: LiveRoomErrorKind.notLive,
        title: "主播暂未开播",
        tip: "",
        icon: Remix.vidicon_line,
        retryable: true,
      );
    case LiveRoomErrorKind.unknown:
      return const LiveRoomErrorInfo(
        kind: LiveRoomErrorKind.unknown,
        title: "直播间加载失败",
        tip: "请刷新重试。如果一直失败，可复制错误信息反馈。",
        icon: Remix.error_warning_line,
        retryable: true,
      );
  }
}

/// 判断错误属于哪一类
LiveRoomErrorKind _classify(Object? error) {
  if (error == null) {
    return LiveRoomErrorKind.unknown;
  }

  // 1) Core 层自己抛的错误：以 HTTP 状态码为准，最可靠
  if (error is CoreError) {
    return _fromStatusCode(error.statusCode, fallback: error.message);
  }

  // 2) dio 的网络异常
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return LiveRoomErrorKind.timeout;
      case DioExceptionType.badResponse:
        return _fromStatusCode(error.response?.statusCode ?? 0);
      case DioExceptionType.cancel:
        return LiveRoomErrorKind.unknown;
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return LiveRoomErrorKind.network;
    }
  }

  // 3) 系统层网络异常
  if (error is SocketException ||
      error is HttpException ||
      error is HandshakeException ||
      error is TlsException) {
    return LiveRoomErrorKind.network;
  }

  // 4) 超时
  if (error is TimeoutException) {
    return LiveRoomErrorKind.timeout;
  }

  // 5) 接口通了但数据结构对不上
  //
  // 抖音主播被封禁 / 房间已关闭时走的就是这条：
  // 接口 200，但 data.room 为空，往下取字段就抛这些。
  if (error is TypeError ||
      error is NoSuchMethodError ||
      error is RangeError ||
      error is StateError) {
    return LiveRoomErrorKind.dataMissing;
  }
  if (error is FormatException) {
    return LiveRoomErrorKind.dataMissing;
  }

  // 6) 退回到消息文本判断（有些站点把原因放在 Exception 的字符串里）
  final msg = error.toString().toLowerCase();
  if (msg.contains("null is not a subtype") ||
      msg.contains("cannot be null") ||
      msg.contains("no such method") ||
      msg.contains("未找到") ||
      msg.contains("不存在") ||
      msg.contains("已关闭") ||
      msg.contains("已封禁") ||
      msg.contains("封禁")) {
    return LiveRoomErrorKind.dataMissing;
  }
  if (msg.contains("timeout") || msg.contains("timed out")) {
    return LiveRoomErrorKind.timeout;
  }
  if (msg.contains("socket") ||
      msg.contains("connection") ||
      msg.contains("network") ||
      msg.contains("failed host lookup")) {
    return LiveRoomErrorKind.network;
  }

  if (_isNotLiveMessage(msg)) {
    return LiveRoomErrorKind.notLive;
  }

  return LiveRoomErrorKind.unknown;
}

/// 按 HTTP 状态码归类
LiveRoomErrorKind _fromStatusCode(int code, {String fallback = ""}) {
  switch (code) {
    case 404:
    case 410:
      return LiveRoomErrorKind.notFound;
    case 401:
    case 403:
    case 412:
    case 418:
    case 429:
      return LiveRoomErrorKind.blocked;
    case 500:
    case 502:
    case 503:
    case 504:
      return LiveRoomErrorKind.server;
  }
  if (code > 0) {
    // 其它 4xx 归到「被限制」，5xx 归到服务端
    return code >= 500 ? LiveRoomErrorKind.server : LiveRoomErrorKind.blocked;
  }
  // 没有状态码时看文案
  final low = fallback.toLowerCase();
  if (low.contains("不存在") || low.contains("not found")) {
    return LiveRoomErrorKind.notFound;
  }
  if (low.contains('封禁') || low.contains('已关闭')) {
    return LiveRoomErrorKind.dataMissing;
  }
  if (_isNotLiveMessage(low)) {
    return LiveRoomErrorKind.notLive;
  }
  return LiveRoomErrorKind.unknown;
}

bool _isNotLiveMessage(String message) {
  return message.contains('未开播') ||
      message.contains('未直播') ||
      message.contains('不在直播') ||
      message.contains('直播已结束') ||
      message.contains('not live') ||
      message.contains('not living');
}
