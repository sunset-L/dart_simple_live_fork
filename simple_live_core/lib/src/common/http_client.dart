import 'package:simple_live_core/src/common/core_error.dart';
import 'package:dio/dio.dart';

import 'custom_interceptor.dart';

class HttpClient {
  static HttpClient? _httpUtil;

  static HttpClient get instance {
    _httpUtil ??= HttpClient();
    return _httpUtil!;
  }

  late Dio dio;
  HttpClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: 20),
        receiveTimeout: Duration(seconds: 20),
        sendTimeout: Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CustomInterceptor());
  }

  /// Get请求，返回String
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: header,
          // 出错时也要把响应体读回来，否则拿不到服务端给出的具体原因
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      throw _toCoreError(e, "发送GET请求失败");
    }
  }

  /// 把 Dio 的异常转换成带**可读原因**的 [CoreError]
  ///
  /// 原来只取 `e.message`，而 Dio 的 message 形如
  /// `This exception was thrown because the response has a status code of 412...`，
  /// 冗长且不含服务端答案。真正有用的是响应体：
  /// B 站 412 时会返回一段 HTML 或 `{"code":-352,...}`，
  /// 有了它才能判断是风控拦截还是签名问题。
  CoreError _toCoreError(Object e, String fallback) {
    if (e is DioException && e.type == DioExceptionType.badResponse) {
      final status = e.response?.statusCode ?? 0;
      return CoreError(
        _extractServerHint(e.response?.data),
        statusCode: status,
      );
    }
    if (e is DioException) {
      // 连接超时 / DNS 解析失败 / TLS 握手失败等
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return CoreError("网络请求超时，请检查网络后重试");
        case DioExceptionType.connectionError:
          return CoreError("无法连接到服务器，请检查网络后重试");
        case DioExceptionType.badCertificate:
          return CoreError("服务器证书校验失败");
        case DioExceptionType.cancel:
          return CoreError("请求已取消");
        default:
          return CoreError("$fallback：${e.message ?? "未知错误"}");
      }
    }
    return CoreError(fallback);
  }

  /// 从响应体里提取一句人类可读的原因，取不到返回空串
  String _extractServerHint(dynamic data) {
    if (data == null) {
      return "";
    }
    if (data is Map) {
      final msg = data["message"] ?? data["msg"] ?? data["error"] ?? "";
      final code = data["code"];
      final text = msg.toString().trim();
      if (text.isNotEmpty && text != code?.toString()) {
        return text;
      }
      return "";
    }
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) {
        return "";
      }
      // HTML 错误页对用户没意义，只给出「服务端返回了网页」这一层信息
      if (text.startsWith("<")) {
        return "服务器返回了网页内容，通常是被风控拦截";
      }
      return text.length > 200 ? "${text.substring(0, 200)}…" : text;
    }
    return "";
  }

  /// Get请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      throw _toCoreError(e, "发送GET请求失败");
    }
  }

  /// Post请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      data ??= {};
      var result = await dio.post(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
          receiveDataWhenStatusError: true,
          contentType:
              formUrlEncoded ? Headers.formUrlEncodedContentType : null,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      throw _toCoreError(e, "发送POST请求失败");
    }
  }

  /// Head请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.head(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: header,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        //throw CoreError(e.message, statusCode: e.response?.statusCode ?? 0);
        return e.response!;
      } else {
        throw CoreError("发送HEAD请求失败");
      }
    }
  }
}
