import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'playback_service.dart';

class MediaProxy {
  MediaProxy(this.playback);
  final PlaybackService playback;
  static final Dio _client =
      Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 30),
          ),
        )
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            return HttpClient()
              ..autoUncompress = false
              ..findProxy = ((_) => 'DIRECT')
              ..connectionFactory = (uri, proxyHost, proxyPort) async {
                // Connect to the validated address, avoiding a second DNS resolution.
                final addresses = await _publicTarget(uri);
                return Socket.startConnect(addresses.first, uri.port);
              };
          },
        );
  static int _active = 0;

  Future<void> serve(HttpRequest request, String token) async {
    final target = playback.proxyTarget(token);
    if (target == null) {
      request.response.statusCode = 410;
      return;
    }
    if (_active >= 32) {
      request.response.statusCode = 503;
      return;
    }
    _active++;
    final cancel = CancelToken();
    var started = false;
    request.response.done.then(
      (_) => cancel.cancel(),
      onError: (_) => cancel.cancel(),
    );
    try {
      var uri = Uri.parse(target.url);
      final initialHost = uri.host;
      Response<ResponseBody>? upstream;
      for (var redirects = 0; redirects < 4; redirects++) {
        upstream = await _client.get<ResponseBody>(
          uri.toString(),
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              ...Map<String, String>.of(target.headers)..removeWhere(
                (key, _) =>
                    uri.host != initialHost &&
                    {'cookie', 'authorization'}.contains(key.toLowerCase()),
              ),
              if (request.headers.value('range') != null)
                'Range': request.headers.value('range'),
              'Accept-Encoding': 'identity',
            },
          ),
        );
        if ([301, 302, 303, 307, 308].contains(upstream.statusCode)) {
          final location = upstream.headers.value('location');
          await upstream.data!.stream.listen(null).cancel();
          if (location == null) throw const HttpException('无效视频重定向');
          uri = uri.resolve(location);
          upstream = null;
        } else {
          break;
        }
      }
      if (upstream == null) throw const HttpException('视频重定向过多');
      final encoding = upstream.headers.value('content-encoding');
      if (encoding != null && encoding != 'identity') {
        await upstream.data!.stream.listen(null).cancel();
        throw const HttpException('不支持的媒体压缩编码');
      }
      if ((upstream.statusCode ?? 500) >= 300) {
        await upstream.data!.stream.listen(null).cancel();
        request.response.statusCode = upstream.statusCode ?? 502;
        return;
      }
      final type =
          upstream.headers.value('content-type') ?? 'application/octet-stream';
      final playlist =
          type.toLowerCase().contains('mpegurl') ||
          uri.path.toLowerCase().contains('.m3u8');
      request.response.statusCode = upstream.statusCode ?? 200;
      request.response.headers.set(
        'Content-Type',
        playlist ? 'application/vnd.apple.mpegurl' : type,
      );
      if (playlist) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in upstream.data!.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const HttpException('播放清单过大');
          }
          bytes.add(chunk);
        }
        final text = utf8.decode(bytes.takeBytes());
        if (!text.trimLeft().startsWith('#EXTM3U')) {
          throw const HttpException('无效播放清单');
        }
        String rewrite(String value) {
          final child = uri.resolve(value);
          if (!{'http', 'https'}.contains(child.scheme)) {
            throw const HttpException('不支持的分片协议');
          }
          final headers = Map<String, String>.of(target.headers);
          if (child.host != initialHost) {
            headers.removeWhere(
              (key, _) =>
                  {'cookie', 'authorization'}.contains(key.toLowerCase()),
            );
          }
          return '/api/playback/proxy/${playback.registerProxy(child.toString(), headers)}';
        }

        final output = text
            .split('\n')
            .map((line) {
              if (line.trim().isEmpty) return line;
              if (!line.startsWith('#')) return rewrite(line.trim());
              return line.replaceAllMapped(
                RegExp(r'URI="([^"]+)"'),
                (match) => 'URI="${rewrite(match[1]!)}"',
              );
            })
            .join('\n');
        request.response.write(output);
      } else {
        for (final header in [
          'content-range',
          'accept-ranges',
          'content-length',
        ]) {
          final value = upstream.headers.value(header);
          if (value != null) request.response.headers.set(header, value);
        }
        started = true;
        await request.response.addStream(upstream.data!.stream);
      }
    } catch (_) {
      cancel.cancel();
      if (!started) {
        request.response.statusCode = 502;
        request.response.write('Media request failed');
      }
    } finally {
      _active--;
    }
  }

  static Future<List<InternetAddress>> _publicTarget(Uri uri) async {
    if (!{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        ![80, 443].contains(uri.port)) {
      throw const HttpException('无效媒体地址');
    }
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 10));
    if (addresses.isEmpty) throw const HttpException('媒体地址不可解析');
    for (final address in addresses) {
      final bytes = address.rawAddress;
      final privateV4 =
          address.type == InternetAddressType.IPv4 &&
          (bytes[0] == 0 ||
              bytes[0] == 10 ||
              bytes[0] == 127 ||
              bytes[0] >= 224 ||
              (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
              (bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)) ||
              (bytes[0] == 192 && bytes[1] == 168) ||
              (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
              (bytes[0] == 169 && bytes[1] == 254));
      final privateV6 =
          address.type == InternetAddressType.IPv6 && (bytes[0] & 0xe0) != 0x20;
      if (address.isLoopback || address.isLinkLocal || privateV4 || privateV6) {
        throw const HttpException('禁止代理本地网络');
      }
    }
    return addresses;
  }
}
