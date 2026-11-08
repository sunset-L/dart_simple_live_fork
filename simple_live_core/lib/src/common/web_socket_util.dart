import 'dart:async';

import 'package:web_socket_channel/io.dart';

enum SocketStatus {
  connected,
  failed,
  closed,
}

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;
  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
  });
  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 最大重连次数
  int maxReconnectTime = 5;

  StreamSubscription<dynamic>? streamSubscription;

  /// 是否已被主动关闭
  /// - 主动关闭（切换直播间、退出页面）后不再自动重连
  bool _manuallyClosed = false;

  void connect({bool retry = false}) async {
    _manuallyClosed = false;

    // 注意：这里不能调用 close()，因为 close() 会把 _manuallyClosed 置为 true
    // 并且会取消正在等待的重连定时器，导致重连彻底失效。
    _reset();

    try {
      var wsurl = url;
      if (backupUrl != null && backupUrl!.isNotEmpty && retry) {
        wsurl = backupUrl!;
      }
      webSocket = IOWebSocketChannel.connect(
        wsurl,
        connectTimeout: Duration(seconds: 10),
        headers: headers,
      );

      await webSocket?.ready;
      ready();
    } catch (e) {
      if (!retry && backupUrl != null && backupUrl!.isNotEmpty) {
        // 主链接失败，尝试备用链接
        connect(retry: true);
        return;
      }
      onError(e, e);
      // 连接失败同样要进入重连流程，否则一次网络抖动就永久断开
      scheduleReconnect();
    }
  }

  /// 连接完成
  void ready() {
    status = SocketStatus.connected;

    streamSubscription = webSocket?.stream.listen(
      (data) => receiveMessage(data),
      onError: (e, s) => onError(e, s),
      onDone: onDone,
    );

    onReady?.call();
    initHeartBeat();
  }

  void initHeartBeat() {
    heartBeatTimer?.cancel();
    heartBeatTimer = Timer.periodic(
      Duration(milliseconds: heartBeatTime),
      (timer) {
        onHeartBeat?.call();
      },
    );
  }

  void receiveMessage(dynamic data) {
    //接受到一条信息才算重连成功
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void onError(e, s) {
    status = SocketStatus.failed;
    onClose?.call(e.toString());
    scheduleReconnect();
  }

  void onDone() {
    if (_manuallyClosed) {
      return;
    }
    onReconnect?.call();
    scheduleReconnect();
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.sink.add(message);
    }
  }

  /// 清理当前连接资源，但不改变「是否主动关闭」的语义
  void _reset() {
    status = SocketStatus.closed;

    streamSubscription?.cancel();
    streamSubscription = null;

    heartBeatTimer?.cancel();
    heartBeatTimer = null;

    try {
      webSocket?.sink.close();
    } catch (_) {
      // 忽略关闭已失效连接的异常
    }
    webSocket = null;
  }

  /// 主动关闭连接
  /// - 主动关闭后不再自动重连
  void close() {
    _manuallyClosed = true;

    reconnectTimer?.cancel();
    reconnectTimer = null;

    _reset();
  }

  /// 安排一次重连
  /// - 使用单次 Timer 并在回调中先清空引用，避免 connect() 内部清理时把定时器取消掉
  void scheduleReconnect() {
    if (_manuallyClosed) {
      return;
    }
    if (reconnectTimer != null) {
      // 已有待执行的重连，避免重复排队
      return;
    }
    if (reconnectTime >= maxReconnectTime) {
      _giveUp();
      return;
    }

    reconnectTime++;
    reconnectTimer = Timer(Duration(seconds: 5), () {
      reconnectTimer = null;
      if (_manuallyClosed || status == SocketStatus.connected) {
        return;
      }
      connect();
    });
  }

  /// 兼容旧调用
  void reconnect() => scheduleReconnect();

  void _giveUp() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    onClose?.call("重连超过最大次数，与服务器断开连接");
    _manuallyClosed = true;
    _reset();
  }
}
