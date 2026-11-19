import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:simple_live_core/simple_live_core.dart';
import '../playback/playback_service.dart';

class DanmakuService {
  DanmakuService(this.playback);
  final PlaybackService playback;
  int _active = 0;
  Future<void> serve(WebSocket socket, Uri uri) async {
    if (_active >= 16) {
      await socket.close(1013, 'busy');
      return;
    }
    _active++;
    final site = uri.queryParameters['site'] ?? '';
    final room = uri.queryParameters['roomId'] ?? '';
    LiveDanmaku? connection;
    var closed = false;
    final queue = <Map<String, dynamic>>[];
    Timer? flush;
    void flushQueue() {
      flush = null;
      if (closed || socket.readyState != WebSocket.open || queue.isEmpty) {
        return;
      }
      socket.add(jsonEncode({'type': 'batch', 'events': List.of(queue)}));
      queue.clear();
    }

    void send(Map<String, dynamic> value) {
      if (!closed &&
          socket.readyState == WebSocket.open &&
          queue.length < 100) {
        queue.add(value);
        flush ??= Timer(const Duration(milliseconds: 100), flushQueue);
      }
    }

    Future<void> cleanup() async {
      if (closed) return;
      closed = true;
      _active--;
      flush?.cancel();
      queue.clear();
      try {
        await connection?.stop();
      } catch (_) {
        // Disconnected upstreams may already have disposed their transport.
      }
    }

    socket.pingInterval = const Duration(seconds: 20);
    socket.listen((_) {}, onDone: cleanup, onError: (_) => cleanup());
    try {
      final detail = await playback.detail(site, room);
      if (closed) return;
      if (!detail.status) {
        await socket.close(1000, 'offline');
        return;
      }
      final live = playback.site(site).getDanmaku();
      connection = live;
      live.onReady = () => send({'type': 'status', 'status': 'ready'});
      live.onClose = (_) => send({
        'type': 'status',
        'status': 'reconnecting',
        'message': '平台弹幕连接中断，正在重试',
      });
      live.onMessage = (value) => send(liveMessageJson(value));
      send({'type': 'status', 'status': 'connecting'});
      await live.start(detail.danmakuData);
      if (closed) await live.stop();
    } catch (_) {
      if (!closed) {
        socket.add(
          jsonEncode({
            'type': 'status',
            'status': 'error',
            'message': '弹幕连接失败，请刷新房间或重新连接',
          }),
        );
        await socket.close(1011, 'upstream');
      }
      await cleanup();
    }
  }
}
