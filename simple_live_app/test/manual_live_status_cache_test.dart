import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/manual_live_status_cache.dart';

void main() {
  test('只在显式刷新时请求，缓存读取及新增历史不会发起请求', () async {
    final cache = ManualLiveStatusCache();
    addTearDown(cache.dispose);
    var calls = 0;
    expect(cache['room'], isNull);
    await cache.refresh({
      'room': () async {
        calls++;
        return true;
      },
    });
    for (var i = 0; i < 100; i++) {
      expect(await cache['room'], isTrue);
      expect(cache['new-room'], isNull);
    }
    expect(calls, 1);
  });

  test('刷新等待全部状态完成，包括尚未读取的离屏条目', () async {
    final cache = ManualLiveStatusCache();
    addTearDown(cache.dispose);
    final first = Completer<bool>();
    final second = Completer<bool>();
    var finished = false;
    final refresh = cache.refresh({
      'first': () => first.future,
      'second': () => second.future,
    }).then((_) => finished = true);
    first.complete(true);
    expect(await cache['first'], isTrue);
    expect(finished, isFalse);
    second.complete(false);
    await refresh;
    expect(await cache['second'], isFalse);
    expect(finished, isTrue);
  });

  test('并发刷新合并，下一轮刷新替换旧缓存', () async {
    final cache = ManualLiveStatusCache();
    addTearDown(cache.dispose);
    final pending = Completer<bool>();
    var calls = 0;
    final first = cache.refresh({
      'first': () {
        calls++;
        return pending.future;
      },
    });
    final overlap = cache.refresh({
      'second': () async {
        calls++;
        return false;
      },
    });
    expect(identical(first, overlap), isTrue);
    expect(calls, 1);
    pending.complete(true);
    await first;
    await cache.refresh({
      'second': () async {
        calls++;
        return false;
      },
    });
    expect(calls, 2);
    expect(cache['first'], isNull);
    expect(await cache['second'], isFalse);
  });

  test('同步和异步查询失败均保留未知状态，不中断刷新', () async {
    final cache = ManualLiveStatusCache();
    addTearDown(cache.dispose);
    await cache.refresh({
      'sync-error': () => throw StateError('failed'),
      'async-error': () async => throw StateError('failed'),
      'success': () async => true,
    });
    expect(await cache['sync-error'], isNull);
    expect(await cache['async-error'], isNull);
    expect(await cache['success'], isTrue);
  });

  test('请求按并发上限排队', () async {
    final cache = ManualLiveStatusCache(maxConcurrent: 2);
    addTearDown(cache.dispose);
    final pending = List.generate(6, (_) => Completer<bool>());
    var calls = 0;
    var active = 0;
    var peak = 0;
    final refresh = cache.refresh({
      for (var i = 0; i < pending.length; i++)
        '$i': () async {
          calls++;
          active++;
          if (active > peak) peak = active;
          final result = await pending[i].future;
          active--;
          return result;
        },
    });
    expect(calls, 2);
    for (final request in pending) {
      request.complete(true);
      await Future<void>.delayed(Duration.zero);
    }
    await refresh;
    expect(calls, 6);
    expect(peak, 2);
  });

  test('关闭面板后不再启动排队请求，空列表刷新可以完成', () async {
    final cache = ManualLiveStatusCache(maxConcurrent: 1);
    final pending = Completer<bool>();
    var calls = 0;
    final refresh = cache.refresh({
      'first': () {
        calls++;
        return pending.future;
      },
      'queued': () async {
        calls++;
        return true;
      },
    });
    cache.dispose();
    pending.complete(true);
    await refresh;
    expect(calls, 1);
    expect(cache['first'], isNull);
    final empty = ManualLiveStatusCache();
    addTearDown(empty.dispose);
    await empty.refresh({});
  });
}
