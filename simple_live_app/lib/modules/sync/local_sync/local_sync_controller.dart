import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/sync/local_sync/qr_scan_page.dart';
import 'package:simple_live_app/requests/sync_client_request.dart';
import 'package:simple_live_app/routes/app_navigation.dart';

import 'package:simple_live_app/services/sync_service.dart';

class LocalSyncController extends BaseController {
  final String? address;
  LocalSyncController(this.address);

  @override
  void onInit() {
    SyncService.instance.refreshClients();
    Future.delayed(Duration.zero, initConnect);
    super.onInit();
  }

  void initConnect() {
    if (address != null && address!.isNotEmpty) {
      addressController.text = address!;
      connect();
    }
  }

  TextEditingController addressController = TextEditingController();
  SyncClientRequest request = SyncClientRequest();

  void connect() async {
    var address = addressController.text;
    if (address.isEmpty) {
      SmartDialog.showToast("请输入地址");
      return;
    }
    if (address.startsWith('http')) {
      var uri = Uri.tryParse(address);
      if (uri != null) {
        address = uri.host;
      }
    } else if (address.contains(':')) {
      var parts = address.split(":");
      address = parts.first;
    }

    var client = SyncClinet(
      id: 'manual',
      address: address,
      port: SyncService.httpPort,
      name: "手动输入",
      type: Platform.operatingSystem,
    );
    connectClient(client);
  }

  Future<void> scanAndConnect() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      SmartDialog.showToast('当前平台不支持摄像头扫码，请手动输入设备地址');
      return;
    }
    final raw = await Get.to<String>(() => const LocalSyncScannerPage());
    if (raw == null || raw.trim().isEmpty) return;

    final value = raw.trim();
    Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, dynamic> &&
        decoded['type'] == 'simple-live-sync') {
      final host = decoded['host'];
      final port = decoded['port'];
      final token = decoded['token'];
      final ip = InternetAddress.tryParse(host is String ? host : '');
      if (decoded['version'] != 1 ||
          ip == null ||
          ip.type != InternetAddressType.IPv4 ||
          !_isLanAddress(ip) ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(token)) {
        SmartDialog.showToast('网页同步二维码无效或不在局域网内');
        return;
      }
      connectClient(
        SyncClinet(
          id: 'web-${ip.address}',
          address: ip.address,
          port: port,
          name: 'Simple Live Web',
          type: 'web',
          syncToken: token,
        ),
      );
      return;
    }

    final legacy = _parseLegacyAddress(value);
    if (legacy == null) {
      SmartDialog.showToast('未识别的同步二维码');
      return;
    }
    addressController.text = legacy.$1;
    connectClient(
      SyncClinet(
        id: 'manual',
        address: legacy.$1,
        port: legacy.$2,
        name: '扫码设备',
        type: Platform.operatingSystem,
      ),
    );
  }

  bool _isLanAddress(InternetAddress address) {
    final octets = address.rawAddress;
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  (String, int)? _parseLegacyAddress(String value) {
    final candidate = value.split(';').first.trim();
    final uri = Uri.tryParse(candidate);
    if (uri != null && ['http', 'https'].contains(uri.scheme)) {
      final ip = InternetAddress.tryParse(uri.host);
      if (ip?.type == InternetAddressType.IPv4) {
        return (ip!.address, uri.hasPort ? uri.port : SyncService.httpPort);
      }
      return null;
    }
    final match = RegExp(
      r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$',
    ).firstMatch(candidate);
    if (match == null) return null;
    final ip = InternetAddress.tryParse(match.group(1)!);
    final port = int.tryParse(match.group(2) ?? '${SyncService.httpPort}');
    if (ip?.type != InternetAddressType.IPv4 ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return (ip!.address, port);
  }

  void connectClient(SyncClinet client) async {
    try {
      SmartDialog.showLoading(msg: "连接中...");
      var info = await request.getClientInfo(client);
      AppNavigator.toSyncDevice(client, info);
    } catch (e) {
      SmartDialog.showToast("连接失败:$e");
    } finally {
      SmartDialog.dismiss();
    }
  }

  void showInfo() {
    Utils.showBottomSheet(
      title: '本机信息',
      child: Column(
        children: [
          Visibility(
            visible: SyncService.instance.httpRunning.value,
            child: GestureDetector(
              onTap: Get.back,
              child: QrImageView(
                data: SyncService.instance.ipAddress.value,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                padding: AppStyle.edgeInsetsA12,
                size: 200,
              ),
            ),
          ),
          AppStyle.vGap24,
          Visibility(
            visible: SyncService.instance.httpRunning.value,
            child: Text(
              '服务已启动：${SyncService.instance.ipAddress.value.split(';').map((e) => '$e:${SyncService.httpPort}').join('；')}',
              textAlign: TextAlign.center,
            ),
          ),
          Visibility(
            visible: !SyncService.instance.httpRunning.value,
            child: Text(
              'HTTP服务未启动：${SyncService.instance.httpErrorMsg}，请尝试重启应用',
              textAlign: TextAlign.center,
            ),
          ),
          AppStyle.vGap12,
          Visibility(
            visible: SyncService.instance.httpRunning.value,
            child: const Text(
              '请使用其他 Simple Live 客户端扫描上方二维码，建立连接后选择同步内容',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
