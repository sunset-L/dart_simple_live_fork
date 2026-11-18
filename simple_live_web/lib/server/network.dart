import 'package:dio/dio.dart';

final network = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    followRedirects: false,
    validateStatus: (_) => true,
  ),
);
