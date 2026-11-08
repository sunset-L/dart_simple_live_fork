import 'dart:async';

/// 只在显式刷新时查询直播状态，读取缓存不会发起请求。
class ManualLiveStatusCache {
  final int maxConcurrent;
  Map<String, Future<bool?>> _statuses = {};
  Future<void>? _refreshing;
  bool _disposed = false;

  ManualLiveStatusCache({this.maxConcurrent = 4}) : assert(maxConcurrent > 0);

  Future<bool?>? operator [](String id) => _statuses[id];

  Future<void> refresh(Map<String, Future<bool> Function()> queries) {
    if (_disposed) {
      return Future.value();
    }
    if (_refreshing != null) {
      return _refreshing!;
    }

    final entries = queries.entries.toList();
    final pending = {
      for (final entry in entries) entry.key: Completer<bool?>(),
    };
    _statuses = {
      for (final entry in pending.entries) entry.key: entry.value.future,
    };
    var next = 0;

    Future<void> worker() async {
      while (!_disposed && next < entries.length) {
        final entry = entries[next++];
        try {
          final status = await entry.value();
          pending[entry.key]!.complete(_disposed ? null : status);
        } catch (_) {
          // 查询失败保持未知状态，离屏条目也不会产生未处理的 Future 错误。
          pending[entry.key]!.complete(null);
        }
      }
    }

    _refreshing = Future.wait([
      for (var i = 0; i < maxConcurrent && i < entries.length; i++) worker(),
    ]).then<void>((_) {}).whenComplete(() {
      for (final request in pending.values) {
        if (!request.isCompleted) {
          request.complete(null);
        }
      }
      _refreshing = null;
    });
    return _refreshing!;
  }

  void dispose() {
    _disposed = true;
    _statuses.clear();
  }
}
