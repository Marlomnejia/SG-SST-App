import 'dart:io';

import 'package:flutter/services.dart';

class DeviceSettingsService {
  static const MethodChannel _channel = MethodChannel('edu_sst/device_settings');

  Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('openNotificationSettings');
    return result == true;
  }

  Future<bool> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('openAppSettings');
    return result == true;
  }

  Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('openAutoStartSettings');
    return result == true;
  }
}
