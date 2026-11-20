import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/utils.dart';
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
    final address = addressController.text.trim();
    if (address.isEmpty) {
      SmartDialog.showToast("请输入地址");
      return;
    }

    final endpoint = _parseLegacyAddress(address);
    if (endpoint == null) {
      SmartDialog.showToast('地址格式无效，请输入 IPv4 地址和端口，例如 192.168.1.10:23239');
      return;
    }

    var client = SyncClinet(
      id: 'manual',
      address: endpoint.$1,
      port: endpoint.$2,
      name: "手动输入",
      type: Platform.operatingSystem,
    );
    connectClient(client);
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
              '在另一台设备的局域网同步页面输入以上 IP 和端口即可连接',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
